// A browser Web Lock owns one writable game context. No time-based lock stealing.
export class WriterLease {
  constructor(lockManager,onChange = ()=>{}) { this.manager=lockManager;this.onChange=onChange;this.state='pending';this.release=null; }
  async acquire(scope) {
    if (!/^[A-Za-z0-9._:-]{1,180}$/.test(scope)) throw Error('invalid_scope');
    if (!this.manager?.request) {this.state='unsupported';this.onChange(this.state);return;}
    if (this.state==='writable') return;
    await new Promise((ready,reject)=>{
      this.manager.request('aethera-rpg:'+scope,{mode:'exclusive',ifAvailable:true},lock=>{
        if(!lock){this.state='readonly';this.onChange(this.state);ready();return;}
        this.state='writable';this.onChange(this.state);ready();
        return new Promise(resolve=>{this.release=resolve;});
      }).catch(error=>{this.state='readonly';this.onChange(this.state);reject(error);});
    });
  }
  close(){this.release?.();this.release=null;this.state='closed';}
}
