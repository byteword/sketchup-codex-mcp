using System;
using Jint;
using System.IO;
using System.Linq;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.Diagnostics;
using System.Reflection;
using System.Collections.Generic;
using System.Runtime.CompilerServices;

namespace SketchUpPipeProbe
{
    public static class LibraryWorker
    {
        static int installed;
        public static void InstallResolver() {
            if(Interlocked.Exchange(ref installed,1)!=0)return;
            AppDomain.CurrentDomain.AssemblyResolve+=(sender,args)=>{
                string name=new AssemblyName(args.Name).Name;
                using(var stream=Assembly.GetExecutingAssembly().GetManifestResourceStream("ProbeRuntime."+name+".dll")) {
                    if(stream==null)return null;
                    using(var m=new MemoryStream()) {stream.CopyTo(m);return Assembly.Load(m.ToArray());}
                }
            };
        }
        public static bool TryMain(string[] args) {
            if(args.Length!=1||args[0]!="--library-worker")return false;
            InstallResolver();
            try {
                string input;using(var reader=new StreamReader(Console.OpenStandardInput(),Lib.Utf8,true))input=reader.ReadToEnd();
                if(Lib.Utf8.GetByteCount(input)>1048576)throw new LibraryFault("budget_exceeded","Worker input too large");
                var result=Execute(Lib.Parse(input));
                WriteOutput(Lib.Map("ok",true,"result",result));
            }catch(Exception error) {
                string type=error.GetType().Name;
                if(error.Message.StartsWith("PROBE_INPUT_INVALID:",StringComparison.Ordinal)) {
                    string diagnostic=error.Message.Substring(20);int split=diagnostic.IndexOf('\t');
                    error=new LibraryFault("input_invalid",split<0?diagnostic:diagnostic.Substring(split+1),split<0?"":diagnostic.Substring(0,split));
                }
                if(!(error is LibraryFault))error=new LibraryFault(type.IndexOf("Parser",StringComparison.Ordinal)>=0?"script_invalid":
                    type.IndexOf("Memory",StringComparison.Ordinal)>=0||type.IndexOf("Statements",StringComparison.Ordinal)>=0||type.IndexOf("Timeout",StringComparison.Ordinal)>=0?"budget_exceeded":"script_failed",error.Message,"technique.js");
                WriteOutput(Lib.Error(error));
            }
            return true;
        }
        static void WriteOutput(object value) {
            byte[] bytes=Lib.Utf8.GetBytes(Lib.Json(value));
            using(var stream=Console.OpenStandardOutput()){stream.Write(bytes,0,bytes.Length);stream.Flush();}
        }
        // Resolver must be installed before the JIT loads Jint signatures.
        [MethodImpl(MethodImplOptions.NoInlining)]
        static object Execute(Dictionary<string,object> request) {
            int ms=Lib.Int(request,"timeout_ms",1000,10,5000);
            int memory=Lib.Int(request,"memory_mib",64,16,256);
            var engine=new Jint.Engine(options=>options.Strict().LimitRecursion(64).LimitMemory(memory*1024L*1024L)
                .MaxStatements(500000).TimeoutInterval(TimeSpan.FromMilliseconds(ms)));
            string script=@"
(function(){
'use strict';
var packages=JSON.parse(PACKAGES_JSON), invocation=JSON.parse(INPUT_JSON), cache=Object.create(null), stack=0;
function freeze(x){if(x && typeof x==='object'){Object.keys(x).forEach(function(k){freeze(x[k]);});Object.freeze(x);}return x;}
Math.random=function(){throw new Error('Nondeterministic random is unavailable');};
Date=undefined; Promise=undefined; SharedArrayBuffer=undefined; Atomics=undefined; WeakRef=undefined;
function eq(a,b){if(a===b)return true;if(!a||!b||typeof a!=='object'||typeof b!=='object')return false;
 var ak=Object.keys(a).sort(),bk=Object.keys(b).sort();return ak.length===bk.length&&ak.every(function(k,i){return k===bk[i]&&eq(a[k],b[k]);});}
function normalize(schema,value,root,n){
 if(n>16)throw new Error('Input nesting budget');
 root=root||schema;
 if(schema.$ref){var name=schema.$ref.substring(8);return normalize(root.$defs[name],value,root,n+1);}
 var type=schema.type;
 if(type==='object'){
  if(!value||typeof value!=='object'||Array.isArray(value))throw new Error('Expected object');
  var output={},properties=schema.properties||{},required=schema.required||[];
  Object.keys(value).forEach(function(k){if(!Object.prototype.hasOwnProperty.call(properties,k))throw new Error('Unknown field '+k);});
  Object.keys(properties).forEach(function(k){var rule=properties[k];
   if(!Object.prototype.hasOwnProperty.call(value,k)){
    if(required.indexOf(k)>=0)throw new Error('Required field '+k);
    if(Object.prototype.hasOwnProperty.call(rule,'default'))output[k]=normalize(rule,JSON.parse(JSON.stringify(rule.default)),root,n+1);
   }else output[k]=normalize(rule,value[k],root,n+1);
  });value=output;
 }else if(type==='array'){
  if(!Array.isArray(value))throw new Error('Expected array');
  value=value.map(function(v){return normalize(schema.items,v,root,n+1);});
  if(schema.minItems!==undefined&&value.length<schema.minItems||schema.maxItems!==undefined&&value.length>schema.maxItems)throw new Error('Array length outside range');
  if(schema.uniqueItems&&value.some(function(v,i){return value.slice(0,i).some(function(w){return eq(v,w);});}))throw new Error('Duplicate item');
 }else if(type==='number'||type==='integer'){
  if(typeof value!=='number'||!isFinite(value)||type==='integer'&&Math.floor(value)!==value)throw new Error('Expected number');
  if(schema.minimum!==undefined&&value<schema.minimum||schema.maximum!==undefined&&value>schema.maximum||
     schema.exclusiveMinimum!==undefined&&value<=schema.exclusiveMinimum||schema.exclusiveMaximum!==undefined&&value>=schema.exclusiveMaximum)throw new Error('Number outside range');
 }else if(type==='string'){
  if(typeof value!=='string')throw new Error('Expected string');
  var length=Array.from(value).length;
  if(schema.minLength!==undefined&&length<schema.minLength||schema.maxLength!==undefined&&length>schema.maxLength)throw new Error('Text length outside range');
 }else if(type==='boolean'&&typeof value!=='boolean'||type==='null'&&value!==null)throw new Error('Unexpected type');
 if(Object.prototype.hasOwnProperty.call(schema,'const')&&!eq(schema.const,value))throw new Error('Const mismatch');
 if(schema.enum&&!schema.enum.some(function(v){return eq(v,value);}))throw new Error('Invalid choice');
 return value;
}
function call(key,params,inputs){
  if(++stack>32)throw new Error('Dependency recursion budget');
  var pack=packages[key]; if(!pack)throw new Error('Missing pinned dependency');
  var context={params:freeze(normalize(pack.schema,params,null,0)),inputs:freeze(inputs||{})};
  context.call=function(alias,p){
    var ref=pack.dependencies[alias];if(!ref)throw new Error('Undeclared dependency');
    return call(ref,p,inputs);
  };
  context.helper=function(alias,p){
    var source=pack.helpers[alias];if(typeof source!=='string')throw new Error('Undeclared helper');
    return new Function('ctx', ""'use strict';\n""+source+""\nreturn build(ctx);"")(freeze({params:p,inputs:context.inputs}));
  };
  var fn=cache[key]||(cache[key]=new Function('ctx',""'use strict';\n""+pack.source+
    ""\nif(typeof validate==='function'){var issues=validate(ctx);if(issues!==undefined&&!Array.isArray(issues))throw new Error('validate(ctx) must return an array');if(issues&&issues.length)throw new Error('PROBE_INPUT_INVALID:'+String(issues[0].path||'')+'\t'+String(issues[0].message||'Invalid input'));}\nreturn build(ctx);""));
  var result=fn(freeze(context));--stack;
  return result;
}
var output=call(ROOT_KEY,invocation.params,invocation.inputs);
function check(x,n){if(n>16)throw new Error('Output nesting budget');
 if(typeof x==='number'&&!isFinite(x))throw new Error('Non-finite output');
 if(x&&typeof x==='object')Object.keys(x).forEach(function(k){check(x[k],n+1);});
 if(typeof x==='function'||typeof x==='undefined')throw new Error('Output is not JSON data');
}
check(output,0);return JSON.stringify(output);
})()";
            engine.SetValue("PACKAGES_JSON",Lib.Json(request["packages"]));
            engine.SetValue("INPUT_JSON",Lib.Json(request["input"]));
            engine.SetValue("ROOT_KEY",Lib.Str(request,"root"));
            string output=engine.Evaluate(script).AsString();
            if(Lib.Utf8.GetByteCount(output)>192*1024)throw new LibraryFault("budget_exceeded","Script output too large");
            var parsed=new System.Web.Script.Serialization.JavaScriptSerializer {MaxJsonLength=196608,RecursionLimit=24}.DeserializeObject(output);
            Lib.TextBudget(parsed,192*1024);return parsed;
        }
        public static async Task<object> RunAsync(Dictionary<string,object> request,CancellationToken token) {
            var info=new ProcessStartInfo(Assembly.GetEntryAssembly().Location,"--library-worker") {
                UseShellExecute=false,CreateNoWindow=true,WindowStyle=ProcessWindowStyle.Hidden,
                RedirectStandardInput=true,RedirectStandardOutput=true,RedirectStandardError=true,
                StandardOutputEncoding=Encoding.UTF8,StandardErrorEncoding=Encoding.UTF8
            };
            using(var p=new Process {StartInfo=info}) {
                p.Start();
                var output=p.StandardOutput.ReadToEndAsync();var errors=p.StandardError.ReadToEndAsync();
                try {
                    // Process.StandardInput inherits the host console code page on .NET Framework.
                    // Write UTF-8 bytes directly; a windowless GUI has no console to reconfigure.
                    byte[] input=Lib.Utf8.GetBytes(Lib.Json(request));
                    await p.StandardInput.BaseStream.WriteAsync(input,0,input.Length).ConfigureAwait(false);
                    p.StandardInput.BaseStream.Close();
                    // Embedded assembly loading/JIT on a cold Windows process is separate from the
                    // unchanged Jint execution budget. Allow bounded startup/serialization overhead.
                    var watch=Stopwatch.StartNew();int limit=Lib.Int(request,"timeout_ms",1000,10,5000)+5000;
                    while(!p.HasExited) {
                        token.ThrowIfCancellationRequested();
                        if(watch.ElapsedMilliseconds>limit||p.PrivateMemorySize64>(Lib.Int(request,"memory_mib",64,16,256)+128L)*1024*1024) {
                            p.Kill();throw new LibraryFault("budget_exceeded","Script worker exceeded time/memory budget");
                        }
                        await Task.Delay(20,token).ConfigureAwait(false);p.Refresh();
                    }
                    string text=await output.ConfigureAwait(false);await errors.ConfigureAwait(false);
                    if(text.Length>196608)throw new LibraryFault("budget_exceeded","Worker result too large");
                    if(String.IsNullOrEmpty(text))throw new LibraryFault("script_failed","Script worker exited without a result");
                    var response=Lib.Parse(text);
                    if(!Lib.Bool(response,"ok")) {
                        var e=Lib.Obj(response["error"]);
                        throw new LibraryFault(Lib.Str(e,"code"),Lib.Str(e,"message"),Lib.Str(e,"path"));
                    }
                    return response["result"];
                }finally {
                    if(!p.HasExited)p.Kill();
                    p.WaitForExit(5000);
                }
            }
        }
    }
}
