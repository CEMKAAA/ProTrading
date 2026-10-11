export function postgresQuery(sql,args=[]) {
  let index=0,quoted=false,out='';
  for(let i=0;i<sql.length;i++){
    const c=sql[i];
    if(c==="'"){out+=c;if(quoted&&sql[i+1]==="'"){out+=sql[++i];continue;}quoted=!quoted;}
    else if(c==='?'&&!quoted)out+='$'+(++index);
    else out+=c;
  }
  if(index!==args.length||quoted)throw new Error('DATABASE_PARAMETER_MISMATCH');
  out=out.replace(/\bAS ([A-Za-z]+[A-Z][A-Za-z]*)/g,'AS "$1"')
    .replace('SET sequence=sequence+1','SET sequence=ea_sequences.sequence+1');
  return {sql:out,args:args.map(x=>x===undefined?null:x)};
}

export class PostgresStore {
  constructor(sql){this.sql=sql;this.savepoints=0;}
  async all(query,...args){const p=postgresQuery(query,args);return Array.from(await this.sql.unsafe(p.sql,p.args));}
  async get(query,...args){return (await this.all(query,...args))[0];}
  async run(query,...args){const p=postgresQuery(query,args),r=await this.sql.unsafe(p.sql,p.args);return {changes:r.count};}
  async deviceAccess(accountId) {
    // Authenticated device proof is checked before this private SQL boundary.
    // All joins use existing PKs; no service key or privileged RPC is exposed.
    const row=await this.get(`SELECT jsonb_build_object(
      'accountId',a.user_id,'email',u.email,'displayName',a.display_name,
      'disabled',a.disabled OR (u.banned_until IS NOT NULL AND u.banned_until>now())
        OR nullif(to_jsonb(u)->>'deleted_at','') IS NOT NULL OR u.email_confirmed_at IS NULL,
      'accessActive',NOT a.disabled AND (u.banned_until IS NULL OR u.banned_until<=now())
        AND nullif(to_jsonb(u)->>'deleted_at','') IS NULL AND u.email_confirmed_at IS NOT NULL
        AND (a.paid_until>now() OR t.expires_at>now()),
      'accessMode',CASE WHEN a.disabled OR (u.banned_until IS NOT NULL AND u.banned_until>now())
        OR nullif(to_jsonb(u)->>'deleted_at','') IS NOT NULL OR u.email_confirmed_at IS NULL THEN 'inactive'
        WHEN a.paid_until>now() THEN 'paid' WHEN t.expires_at>now() THEN 'demo' ELSE 'inactive' END,
      'paidUntil',extract(epoch from a.paid_until)*1000,
      'trial',jsonb_build_object('startsAt',extract(epoch from t.started_at)*1000,'expiresAt',extract(epoch from t.expires_at)*1000),
      'serverNow',extract(epoch from now())*1000) AS state
      FROM stratum_private.accounts a JOIN stratum_private.trial_claims t USING(email_hash)
      JOIN auth.users u ON u.id=a.user_id WHERE a.user_id=?::uuid`,accountId);
    return row?.state??null;
  }
  async syncAuthority(v){
    // One statement preserves the same verified values without five network round trips.
    return this.run(`WITH account AS (
      INSERT INTO accounts(id,entitlement_until,disabled) VALUES(?,?,?)
      ON CONFLICT(id) DO UPDATE SET entitlement_until=excluded.entitlement_until,disabled=excluded.disabled RETURNING id
    ), trial AS (
      INSERT INTO account_trials SELECT id,?,? FROM account
      ON CONFLICT(account_id) DO UPDATE SET starts_at=excluded.starts_at,expires_at=excluded.expires_at
    ), profile AS (
      INSERT INTO account_profiles SELECT id,? FROM account
      ON CONFLICT(account_id) DO UPDATE SET display_name=excluded.display_name
    ), authority AS (
      INSERT INTO supabase_accounts SELECT id,?,? FROM account
      ON CONFLICT(account_id) DO UPDATE SET email=excluded.email,authority_until=excluded.authority_until
    ) UPDATE trading SET enabled=0,revision=revision+1 WHERE account_id IN(SELECT id FROM account) AND ?=0`,
      v.accountId,v.paidUntil,v.disabled,v.startsAt,v.expiresAt,v.name,v.email,v.authorityUntil,v.accessActive);
  }
  async sessionSnapshot(tokenHash){
    return this.get(`SELECT s.id AS sessionId,s.account_id AS accountId,s.expires_at AS sessionExpiry,
      a.disabled,a.entitlement_until AS paidUntil,t.starts_at AS trialStartsAt,t.expires_at AS trialExpiresAt,
      r.account_id AS remoteAccountId,r.authority_until AS authorityUntil,r.email,p.display_name AS profileName,i.email AS localEmail,
      l.installation_id AS leaseInstallationId,l.expires_at AS leaseExpiresAt,l.session_id AS leaseSessionId,
      CASE WHEN tr.account_id IS NULL THEN jsonb_build_object('enabled',false,'jobId',null,'revision',0)
        ELSE jsonb_build_object('enabled',tr.enabled<>0,'jobId',tr.job_id,'revision',tr.revision,'installationId',tr.installation_id) END AS trading,
      COALESCE((SELECT jsonb_agg(to_jsonb(items)) FROM (
        SELECT id,label,state,created_at AS "createdAt" FROM installations WHERE account_id=a.id ORDER BY created_at DESC
      ) items),'[]'::jsonb) AS installations,
      COALESCE((SELECT jsonb_agg(ts.status_json::jsonb||jsonb_build_object('installationId',ts.installation_id,'reportedAt',ts.at))
        FROM terminal_status ts JOIN installations owned ON owned.id=ts.installation_id WHERE owned.account_id=a.id),'[]'::jsonb) AS statuses
      FROM sessions s JOIN accounts a ON a.id=s.account_id LEFT JOIN account_trials t ON t.account_id=a.id
      LEFT JOIN supabase_accounts r ON r.account_id=a.id LEFT JOIN account_profiles p ON p.account_id=a.id
      LEFT JOIN identities i ON i.account_id=a.id LEFT JOIN leases l ON l.account_id=a.id LEFT JOIN trading tr ON tr.account_id=a.id
      WHERE s.token_hash=?`,tokenHash);
  }
  // The Edge request owns one transaction. Nested core atomic() calls never open another connection.
  async atomic(work){
    const point='stratum_'+(++this.savepoints);
    await this.sql.unsafe('SAVEPOINT '+point);
    try{const result=await work();await this.sql.unsafe('RELEASE SAVEPOINT '+point);return result;}
    catch(error){await this.sql.unsafe('ROLLBACK TO SAVEPOINT '+point);await this.sql.unsafe('RELEASE SAVEPOINT '+point);throw error;}
  }
}
