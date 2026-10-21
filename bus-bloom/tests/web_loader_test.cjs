const fs=require('fs');const vm=require('vm');const path=require('path');
const root=path.resolve('sites/cargo-yard-preview/dist');
const source=fs.readFileSync(path.join(root,'wasm-loader.js'),'utf8');
const files=JSON.parse(source.match(/const files = (.*);/)[1]);
const element=()=>({style:{},appendChild(){},remove(){},textContent:''});
(async()=>{
 for(const packed of [true]){
  let requests=0;
  const context={URL,Request,Response,ReadableStream,AbortController,Map,Uint8Array,setTimeout,clearTimeout,location:{href:'https://test.local/',origin:'https://test.local',reload(){}},document:{createElement:element,body:element()}};
  if(packed)context.DecompressionStream=DecompressionStream;
  context.window={fetch:async url=>{requests++;return new Response(fs.readFileSync(path.join(root,new URL(url).pathname.slice(1))),{headers:{'Content-Type':'application/octet-stream'}});}};
  vm.createContext(context);vm.runInContext(source,context);
  for(const [name,file]of Object.entries(files)){
   const response=await context.window.fetch('https://test.local/'+name);
   const actual=Buffer.from(await response.arrayBuffer());
   const expected=Buffer.concat(Array.from({length:file.parts},(_,i)=>require('zlib').gunzipSync(fs.readFileSync(path.join(root,name+'.part'+i+'.gzdata')))));
   if(!actual.equals(expected))throw new Error('Byte mismatch '+name);
  }
  context.window.CargoBoot.done();console.log(packed?'Gzip verified':'Raw fallback verified',requests);
 }
})().catch(e=>{console.error(e);process.exit(1)});
