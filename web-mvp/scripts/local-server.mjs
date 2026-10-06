// Private IPC allows graceful shutdown on Windows without killing other servers.
const service=process.argv[2];
process.argv.splice(2,1);
function stop(){if(!process.emit('SIGTERM'))process.exit(0);}
process.on('message',message=>{if(message==='stratum-shutdown')stop();});
process.once('disconnect',stop);
if(service==='control')await import('../control-service/start.mjs');
else if(service==='web')await import('./run-framework.mjs');
else throw new Error('Unknown local service.');
