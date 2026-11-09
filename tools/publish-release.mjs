// Operator-only release upload using the existing Git credential helper.
// Tokens remain in this process; no credentials or private signing files are uploaded.
import {readFile} from 'node:fs/promises';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import assert from 'node:assert/strict';
const version='1.0.0',repo='chaitanya251203/topolina-expenses-app';
const run=(args,input)=>{
  const result=spawnSync('git',args,{input,encoding:'utf8',env:{...process.env,GIT_TERMINAL_PROMPT:'0',GCM_INTERACTIVE:'never'},windowsHide:true});
  if(result.status!==0)throw new Error('Git prerequisite failed.');return result.stdout.trim();
};
if(process.argv[2]!=='--publish')throw new Error('Review the verified artifact and run with --publish.');
assert.equal(run(['status','--porcelain']),'','Commit the release before uploading it.');
const head=run(['rev-parse','HEAD']);assert.equal(run(['ls-remote','origin','refs/heads/main']).split(/\s+/)[0],head,'Push main first.');
const credentials=run(['credential','fill'],'protocol=https\nhost=github.com\n\n');
const token=credentials.split('\n').find(line=>line.startsWith('password='))?.slice(9).trim();assert.ok(token,'GitHub login required.');
const headers={Authorization:`Bearer ${token}`,Accept:'application/vnd.github+json','X-GitHub-Api-Version':'2022-11-28','User-Agent':'Topolina-Release'};
const api=async(path,options={})=>{
  const response=await fetch(`https://api.github.com/repos/${repo}${path}`,{...options,headers:{...headers,...options.headers}});
  if(!response.ok)throw new Error(`GitHub release operation failed (${response.status}).`);return response.json();
};
const artifact=new URL(`../build/releases/Topolina-${version}-release.apk`,import.meta.url);
const bytes=await readFile(artifact),checksum=createHash('sha256').update(bytes).digest('hex');
const metadata=JSON.parse(await readFile(new URL('../build/releases/manifest.json',import.meta.url),'utf8'));
assert.equal(metadata.sha256,checksum);assert.equal(metadata.signatureVerified,true);assert.equal(metadata.versionName,version);
const releases=await api('/releases');let release=releases.find(r=>r.tag_name===`v${version}`);
if(!release){
  const notes=await readFile(new URL('../docs/release-1.0.0.md',import.meta.url),'utf8');
  release=await api('/releases',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({tag_name:`v${version}`,target_commitish:head,name:`Topolina ${version}`,draft:true,prerelease:false,body:notes})});
}
const fileName=`Topolina-${version}-release.apk`,existing=release.assets.find(a=>a.name===fileName);
if(existing){assert.equal(existing.digest,`sha256:${checksum}`,'A different artifact already exists.');}
else{
  const upload=release.upload_url.replace(/\{.*$/,'')+`?name=${encodeURIComponent(fileName)}`;
  const response=await fetch(upload,{method:'POST',headers:{...headers,'Content-Type':'application/vnd.android.package-archive','Content-Length':bytes.length.toString()},body:bytes});
  if(!response.ok)throw new Error(`APK upload failed (${response.status}).`);
  const asset=await response.json();assert.equal(asset.size,bytes.length);
  if(asset.digest)assert.equal(asset.digest,`sha256:${checksum}`);
}
release=await api(`/releases/${release.id}`,{method:'PATCH',headers:{'Content-Type':'application/json'},body:JSON.stringify({draft:false,make_latest:'true'})});
const saved=await api(`/releases/${release.id}`);const asset=saved.assets.find(a=>a.name===fileName);assert.equal(saved.draft,false);assert.equal(asset.size,bytes.length);
console.log(JSON.stringify({release:saved.html_url,apk:asset.browser_download_url,bytes:asset.size,sha256:checksum,commit:head}));
