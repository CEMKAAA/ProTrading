import { ControlPlane } from "./control-plane.mjs";
import { fileURLToPath } from "node:url";
if(process.argv[2]!=="--local-dev"||process.env.NODE_ENV==="production")throw new Error("Local operator only");
const email=process.argv[3]?.toLowerCase();if(!email)throw new Error("Usage: --local-dev email@example.com");
const plane=new ControlPlane({database:fileURLToPath(new URL("./.state/control.sqlite",import.meta.url))});
try{const row=plane.get("SELECT account_id FROM identities WHERE email=?",email);if(!row)throw new Error("Register first");plane.provisionAccount(row.account_id,Date.now()+86400000);console.log("One-day LOCAL PILOT entitlement granted. Not a payment.");}finally{plane.close();}
