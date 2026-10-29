using System;
using System.IO;
using System.Linq;
using System.Text;
using System.Collections;
using System.Collections.Generic;
using System.Security.Cryptography;
using System.Text.RegularExpressions;
using System.Reflection;

namespace SketchUpPipeProbe
{
    public sealed class LibraryFault : ArgumentException
    {
        public readonly string Code, Path;
        public LibraryFault(string code,string message,string path="") : base(message) { Code=code; Path=path; }
    }
    public static class Lib
    {
        public static readonly UTF8Encoding Utf8=new UTF8Encoding(false,true);
        public static Dictionary<string,object> Map(params object[] pairs) {
            var d=new Dictionary<string,object>(); for(int i=0;i<pairs.Length;i+=2)d[(string)pairs[i]]=pairs[i+1]; return d;
        }
        public static Dictionary<string,object> Obj(object value) {
            var d=value as Dictionary<string,object>; if(d==null)throw new LibraryFault("input_invalid","Expected an object"); return d;
        }
        public static object Get(IDictionary<string,object> d,string k,object fallback=null) { object v; return d.TryGetValue(k,out v)?v:fallback; }
        public static string Str(IDictionary<string,object> d,string k,string fallback="") { var v=Get(d,k,fallback); if(!(v is string))throw new LibraryFault("input_invalid","Expected text: "+k,"/"+k); return (string)v; }
        public static bool Bool(IDictionary<string,object> d,string k,bool fallback=false) { var v=Get(d,k,fallback); if(!(v is bool))throw new LibraryFault("input_invalid","Expected boolean: "+k);return (bool)v; }
        public static IList Arr(object v) { var a=v as IList; if(a==null)throw new LibraryFault("input_invalid","Expected an array"); return a; }
        public static int Int(IDictionary<string,object> d,string k,int fallback,int min,int max) {
            var n=Get(d,k,fallback); if(!Numeric(n))throw new LibraryFault("input_invalid","Expected integer: "+k);
            double v=Convert.ToDouble(n); if(v!=Math.Truncate(v)||v<min||v>max)throw new LibraryFault("input_invalid","Integer out of bounds: "+k);return (int)v;
        }
        public static bool Numeric(object v) { return v is int||v is long||v is double||v is decimal||v is float; }
        public static string Json(object v) { return JsonLines.Serialize(v); }
        public static bool Equal(object a,object b) {
            if(a==null||b==null)return a==b;
            if(Numeric(a)&&Numeric(b))return Convert.ToDouble(a)==Convert.ToDouble(b);
            var ad=a as IDictionary<string,object>;var bd=b as IDictionary<string,object>;
            if(ad!=null&&bd!=null)return ad.Count==bd.Count&&ad.All(p=>bd.ContainsKey(p.Key)&&Equal(p.Value,bd[p.Key]));
            var aa=a as IList;var ba=b as IList;
            if(aa!=null&&ba!=null)return aa.Count==ba.Count&&aa.Cast<object>().Select((x,i)=>Equal(x,ba[i])).All(x=>x);
            return a.Equals(b);
        }
        public static object Canon(object v) {
            var d=v as IDictionary<string,object>; if(d!=null)return d.OrderBy(p=>p.Key,StringComparer.Ordinal).ToDictionary(p=>p.Key,p=>Canon(p.Value));
            var a=v as IList; if(a!=null)return a.Cast<object>().Select(Canon).ToArray(); return v;
        }
        public static string Hash(byte[] b) { using(var h=SHA256.Create())return BitConverter.ToString(h.ComputeHash(b)).Replace("-","").ToLowerInvariant(); }
        public static string Digest(object v) { return "sha256:"+Hash(Utf8.GetBytes(Json(Canon(v)))); }
        public static object Clone(object v) { return new System.Web.Script.Serialization.JavaScriptSerializer {MaxJsonLength=1048576,RecursionLimit=32}.DeserializeObject(Json(v)); }
        public static Dictionary<string,object> Parse(string s) { return JsonLines.Parse(s); }
        public static string Id(IDictionary<string,object> d,string k,string pattern) {
            string s=Str(d,k); if(!Regex.IsMatch(s,"\\A(?:"+pattern+")\\z",RegexOptions.CultureInvariant,TimeSpan.FromMilliseconds(100)))throw new LibraryFault("input_invalid","Invalid "+k,"/"+k);return s;
        }
        public const string TechniquePattern="[a-z][a-z0-9-]{0,31}\\.[a-z][a-z0-9-]{0,63}";
        public const string RevisionPattern="sha256:[0-9a-f]{64}";
        public static string Revision(Dictionary<string,string> files) {
            using(var m=new MemoryStream()) {
                byte[] prefix=Utf8.GetBytes("probe-technique/1\n");m.Write(prefix,0,prefix.Length);
                foreach(var p in files.OrderBy(p=>p.Key,StringComparer.Ordinal)) {
                    byte[] b=Utf8.GetBytes(p.Value.Replace("\r\n","\n"));
                    byte[] key=Utf8.GetBytes(p.Key+"\0"+b.Length.ToString(System.Globalization.CultureInfo.InvariantCulture)+"\0");
                    m.Write(key,0,key.Length);m.Write(b,0,b.Length);
                }
                return "sha256:"+Hash(m.ToArray());
            }
        }
        public static object Read(string path) { return Parse(File.ReadAllText(path,Utf8)); }
        public static void Atomic(string path,object value) {
            Directory.CreateDirectory(System.IO.Path.GetDirectoryName(path));
            string tmp=path+"."+Guid.NewGuid().ToString("N")+".tmp";
            byte[] bytes=Utf8.GetBytes(Json(value));
            using(var f=new FileStream(tmp,FileMode.CreateNew,FileAccess.Write,FileShare.None)) { f.Write(bytes,0,bytes.Length);f.Flush(true); }
            if(File.Exists(path))File.Replace(tmp,path,null);else File.Move(tmp,path);
        }
        public static string Resource(string name) {
            using(var s=Assembly.GetExecutingAssembly().GetManifestResourceStream("ProbeRuntime."+name)) {
                if(s==null)throw new LibraryFault("runtime_missing","Missing bundled resource: "+name);
                using(var r=new StreamReader(s,Utf8))return r.ReadToEnd();
            }
        }
        static string Short(string s,int n) {if(s.Length<=n)return s;if(Char.IsHighSurrogate(s[n-1]))--n;return s.Substring(0,n);}
        public static Dictionary<string,object> Error(Exception e,string effect="none") {
            var f=e as LibraryFault;
            var detail=Map("code",f==null?"library_error":f.Code,"message",Short(e.Message,2048),"path",f==null?"":Short(f.Path,512),
                "retry",effect=="unknown"?"query_first":"never");
#if PROBE_TEST
            detail["debug_type"]=e.GetType().FullName;detail["debug_stack"]=e.StackTrace;
#endif
            return Map("ok",false,"effect",effect,"error",detail);
        }
        public static void TextBudget(object v,int bytes=1048576,int depth=16) {
            if(Utf8.GetByteCount(Json(v))>bytes)throw new LibraryFault("budget_exceeded","JSON byte budget exceeded");
            Action<object,int> walk=null; walk=(x,n)=>{
                if(n>depth)throw new LibraryFault("budget_exceeded","JSON nesting budget exceeded");
                if(Numeric(x)&&!Double.IsNaN(Convert.ToDouble(x))&&!Double.IsInfinity(Convert.ToDouble(x)))return;
                if(x==null||x is string||x is bool)return;
                var d=x as IDictionary<string,object>;if(d!=null) { foreach(var p in d)walk(p.Value,n+1);return; }
                var a=x as IList;if(a!=null) { foreach(var item in a)walk(item,n+1);return; }
                throw new LibraryFault("input_invalid","Unsupported or non-finite JSON value");
            };walk(v,0);
        }
    }

    public static class LibrarySchema
    {
        public static Dictionary<string,object> Bundled(string name) { return Lib.Parse(Lib.Resource(name+".schema.json")); }
        static bool Same(object a,object b) { return Lib.Equal(a,b); }
        public static void Validate(object raw,object value,string path="",Dictionary<string,object> root=null,int depth=0) {
            if(depth>32)throw new LibraryFault("schema_unsupported","Recursive schema");
            if(raw is bool) { if(!(bool)raw)Bad(path,"Value is forbidden");return; }
            var s=Lib.Obj(raw);root=root??s;
            if(s.ContainsKey("$ref")) { Validate(Resolve(root,Lib.Str(s,"$ref")),value,path,root,depth+1);return; }
            if(s.ContainsKey("const")&&!Same(s["const"],value))Bad(path,"Value does not match const");
            if(s.ContainsKey("enum")&&!Lib.Arr(s["enum"]).Cast<object>().Any(x=>Same(x,value)))Bad(path,"Value is not an allowed choice");
            foreach(string key in new[]{"allOf","anyOf","oneOf"})if(s.ContainsKey(key)) {
                int valid=0;foreach(var clause in Lib.Arr(s[key]))try {Validate(clause,value,path,root,depth+1);++valid;}catch(LibraryFault e){if(e.Code!="input_invalid")throw;}
                int total=Lib.Arr(s[key]).Count;if((key=="allOf"&&valid!=total)||(key=="anyOf"&&valid==0)||(key=="oneOf"&&valid!=1))Bad(path,key+" conditions did not match");
            }
            if(s.ContainsKey("if")) {
                bool yes=true;try {Validate(s["if"],value,path,root,depth+1);}catch(LibraryFault e){if(e.Code!="input_invalid")throw;yes=false;}
                string branch=yes?"then":"else";if(s.ContainsKey(branch))Validate(s[branch],value,path,root,depth+1);
            }
            if(s.ContainsKey("type")) {
                object t=s["type"];var choices=t is string?new object[]{t}:Lib.Arr(t).Cast<object>().ToArray();
                if(!choices.Any(k=>Type((string)k,value)))Bad(path,"Unexpected JSON type");
            }
            var d=value as Dictionary<string,object>;
            if(d!=null) {
                var props=Lib.Get(s,"properties",Lib.Map()) as Dictionary<string,object>;
                if(s.ContainsKey("required"))foreach(string k in Lib.Arr(s["required"]))if(!d.ContainsKey(k))Bad(path+"/"+k,"Required property missing");
                Range(s,"minProperties","maxProperties",d.Count,path);
                foreach(var p in d) {
                    object schema;
                    if(props.TryGetValue(p.Key,out schema))Validate(schema,p.Value,path+"/"+p.Key,root,depth+1);
                    else if(s.ContainsKey("additionalProperties"))Validate(s["additionalProperties"],p.Value,path+"/"+p.Key,root,depth+1);
                }
            }
            var a=value as IList;
            if(a!=null) {
                Range(s,"minItems","maxItems",a.Count,path);
                if(Lib.Get(s,"uniqueItems",false).Equals(true)&&a.Cast<object>().Select(x=>Lib.Json(Lib.Canon(x))).Distinct().Count()!=a.Count)Bad(path,"Duplicate array values");
                if(s.ContainsKey("items"))for(int i=0;i<a.Count;i++)Validate(s["items"],a[i],path+"/"+i,root,depth+1);
            }
            var str=value as string;
            if(str!=null) {
                Range(s,"minLength","maxLength",str.EnumerateCodePoints(),path);
                if(s.ContainsKey("pattern")&&!Regex.IsMatch(str,Lib.Str(s,"pattern"),RegexOptions.CultureInvariant,TimeSpan.FromMilliseconds(50)))Bad(path,"Text pattern did not match");
            }
            if(Lib.Numeric(value)) {
                double n=Convert.ToDouble(value);if(Double.IsNaN(n)||Double.IsInfinity(n))Bad(path,"Non-finite number");
                if(s.ContainsKey("minimum")&&n<Convert.ToDouble(s["minimum"])||s.ContainsKey("maximum")&&n>Convert.ToDouble(s["maximum"])||
                   s.ContainsKey("exclusiveMinimum")&&n<=Convert.ToDouble(s["exclusiveMinimum"])||s.ContainsKey("exclusiveMaximum")&&n>=Convert.ToDouble(s["exclusiveMaximum"]))Bad(path,"Number outside range");
            }
        }
        static void Range(Dictionary<string,object>s,string lo,string hi,int n,string p) {if(s.ContainsKey(lo)&&n<Convert.ToInt32(s[lo])||s.ContainsKey(hi)&&n>Convert.ToInt32(s[hi]))Bad(p,"Length outside range");}
        static bool Type(string t,object x) {return t=="null"?x==null:t=="object"?x is Dictionary<string,object>:t=="array"?x is IList:t=="string"?x is string:t=="boolean"?x is bool:t=="number"?Lib.Numeric(x):t=="integer"&&Lib.Numeric(x)&&Convert.ToDouble(x)==Math.Truncate(Convert.ToDouble(x));}
        static void Bad(string p,string m) {throw new LibraryFault("input_invalid",m,p);}
        static object Resolve(Dictionary<string,object> root,string path) {
            if(!path.StartsWith("#/$defs/")||path.IndexOf('/',8)>=0)throw new LibraryFault("schema_unsupported","Only local $defs references supported");
            var defs=Lib.Obj(Lib.Get(root,"$defs",Lib.Map()));object v;if(!defs.TryGetValue(path.Substring(8),out v))throw new LibraryFault("schema_unsupported","Unresolved local schema");return v;
        }
        public static void CheckInput(Dictionary<string,object> root) {
            string[] allowed={"$schema","$defs","$ref","title","description","type","properties","required","additionalProperties","items","minItems","maxItems","uniqueItems","minProperties","maxProperties","minLength","maxLength","minimum","maximum","exclusiveMinimum","exclusiveMaximum","enum","const","default"};
            Action<object,int,HashSet<string>> visit=null;
            visit=(raw,depth,refs)=>{
                if(depth>16)throw new LibraryFault("schema_unsupported","Schema nesting too deep");
                var s=Lib.Obj(raw);
                foreach(string k in s.Keys)if(!allowed.Contains(k))throw new LibraryFault("schema_unsupported","Unsupported schema keyword: "+k);
                if(s.ContainsKey("$ref")) {
                    string r=Lib.Str(s,"$ref");if(!refs.Add(r))throw new LibraryFault("schema_unsupported","Recursive reference");
                    visit(Resolve(root,r),depth+1,refs);refs.Remove(r);return;
                }
                foreach(string bound in new[]{"minimum","maximum","exclusiveMinimum","exclusiveMaximum"})
                    if(s.ContainsKey(bound)&&!Lib.Numeric(s[bound]))throw new LibraryFault("schema_unsupported","Numeric bound required");
                foreach(string count in new[]{"minLength","maxLength","minItems","maxItems","minProperties","maxProperties"})
                    if(s.ContainsKey(count))Lib.Int(s,count,0,0,4096);
                if(s.ContainsKey("enum")&&(Lib.Arr(s["enum"]).Count==0||Lib.Arr(s["enum"]).Count>128))throw new LibraryFault("schema_unsupported","Enum must have1..128 values");
                string t=Lib.Str(s,"type");
                if(!new[]{"object","array","number","integer","string","boolean","null"}.Contains(t))throw new LibraryFault("schema_unsupported","Explicit single type required");
                if(t=="object") {
                    if(!s.ContainsKey("additionalProperties")||!s["additionalProperties"].Equals(false))throw new LibraryFault("schema_unsupported","Input objects must be closed");
                    var props=Lib.Obj(Lib.Get(s,"properties",Lib.Map()));if(props.Count>64)throw new LibraryFault("schema_unsupported","Too many properties");
                    foreach(var p in props)visit(p.Value,depth+1,refs);
                    foreach(string key in Lib.Arr(Lib.Get(s,"required",new object[0])))if(!props.ContainsKey(key))throw new LibraryFault("schema_unsupported","Unknown required field");
                }
                if(t=="array") {if(!s.ContainsKey("maxItems")||Convert.ToInt32(s["maxItems"])>4096)throw new LibraryFault("schema_unsupported","Bounded arrays required");visit(s["items"],depth+1,refs);}
                if(t=="string"&&(!s.ContainsKey("maxLength")||Convert.ToInt32(s["maxLength"])>4096))throw new LibraryFault("schema_unsupported","Bounded text required");
                if(s.ContainsKey("default"))Validate(s,s["default"],"",root);
            };visit(root,0,new HashSet<string>());
            if(root.ContainsKey("$defs"))foreach(var definition in Lib.Obj(root["$defs"]))visit(definition.Value,0,new HashSet<string>());
        }
        public static object Normalize(Dictionary<string,object>s,object value,Dictionary<string,object> root=null) {
            root=root??s;if(s.ContainsKey("$ref"))return Normalize(Lib.Obj(Resolve(root,Lib.Str(s,"$ref"))),value,root);
            var d=value as Dictionary<string,object>;
            if(d!=null) {
                d=Lib.Obj(Lib.Clone(d));var props=Lib.Obj(Lib.Get(s,"properties",Lib.Map()));var required=Lib.Arr(Lib.Get(s,"required",new object[0])).Cast<string>().ToArray();
                foreach(var p in props) {
                    var rule=Lib.Obj(p.Value);
                    if(!d.ContainsKey(p.Key)&&!required.Contains(p.Key)&&rule.ContainsKey("default"))d[p.Key]=Lib.Clone(rule["default"]);
                    if(d.ContainsKey(p.Key))d[p.Key]=Normalize(rule,d[p.Key],root);
                }return d;
            }
            var a=value as IList;if(a!=null&&s.ContainsKey("items"))return a.Cast<object>().Select(x=>Normalize(Lib.Obj(s["items"]),x,root)).ToArray();
            return value;
        }
        static int EnumerateCodePoints(this string s) {
            int n=0;for(int i=0;i<s.Length;++i,++n)if(Char.IsHighSurrogate(s[i])) {if(i+1>=s.Length||!Char.IsLowSurrogate(s[++i]))Bad("","Invalid Unicode");} else if(Char.IsLowSurrogate(s[i]))Bad("","Invalid Unicode");return n;
        }
    }
}
