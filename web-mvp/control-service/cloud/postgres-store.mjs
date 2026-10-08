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
  // The Edge request owns one transaction. Nested core atomic() calls never open another connection.
  async atomic(work){
    const point='stratum_'+(++this.savepoints);
    await this.sql.unsafe('SAVEPOINT '+point);
    try{const result=await work();await this.sql.unsafe('RELEASE SAVEPOINT '+point);return result;}
    catch(error){await this.sql.unsafe('ROLLBACK TO SAVEPOINT '+point);await this.sql.unsafe('RELEASE SAVEPOINT '+point);throw error;}
  }
}
