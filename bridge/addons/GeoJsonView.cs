using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Collections.Generic;
using System.Linq;
using System.Windows.Forms;

namespace SketchUpPipeProbe
{
    // Offline vector preview. Coordinates stay in GeoJSON longitude/latitude order.
    public sealed class GeoJsonView:Control
    {
        struct Coordinate {public double X,Y;public Coordinate(double x,double y){X=x;Y=y;}}
        sealed class Shape {public List<Coordinate[]> Rings=new List<Coordinate[]>();public Coordinate? Point;public string Label;public object Properties;}
        readonly List<Shape> shapes=new List<Shape>();
        double minX,maxX,minY,maxY;float zoom=1,panX,panY;Point drag;bool dragging,moved;
        public event Action<object> FeatureSelected;
        public GeoJsonView(){DoubleBuffered=true;BackColor=Color.FromArgb(246,249,248);Dock=DockStyle.Fill;TabStop=true;}
        public void SetData(Dictionary<string,object> geojson) {
            shapes.Clear();ResetView();
            if(geojson==null){Invalidate();return;}
            try {
                var features=Lib.Arr(geojson["features"]);if(features.Count>100)throw new ArgumentException("Preview feature limit");
                int count=0;
                foreach(object value in features) {
                    var f=Lib.Obj(value);var g=Lib.Obj(f["geometry"]);var s=new Shape {Properties=f["properties"],Label=Lib.Str(Lib.Obj(f["properties"]),"label")};
                    if(Lib.Str(g,"type")=="Point")s.Point=Project(g["coordinates"]);
                    else {
                        var polygons=Lib.Str(g,"type")=="Polygon"?new object[]{g["coordinates"]}:Lib.Arr(g["coordinates"]).Cast<object>().ToArray();
                        foreach(object poly in polygons)foreach(object ring in Lib.Arr(poly)) {
                            var points=Lib.Arr(ring).Cast<object>().Select(Project).ToArray();count+=points.Length;
                            if(count>8000 || points.Length<4)throw new ArgumentException("Preview geometry limit");s.Rings.Add(points);
                        }
                    }
                    shapes.Add(s);
                }
                var all=shapes.SelectMany(s=>s.Point.HasValue?new[]{s.Point.Value}:s.Rings.SelectMany(r=>r)).ToArray();
                if(all.Length>0){minX=all.Min(p=>p.X);maxX=all.Max(p=>p.X);minY=all.Min(p=>p.Y);maxY=all.Max(p=>p.Y);}
            }catch{shapes.Clear();throw;}
            Invalidate();
        }
        static Coordinate Project(object value) {
            var a=Lib.Arr(value);double lon=Convert.ToDouble(a[0]),lat=Convert.ToDouble(a[1]);
            if(Double.IsNaN(lon)||Double.IsInfinity(lon)||Double.IsNaN(lat)||Double.IsInfinity(lat)||Math.Abs(lon)>180||Math.Abs(lat)>90)throw new ArgumentException("Preview coordinates");
            lat=Math.Max(-85,Math.Min(85,lat));
            return new Coordinate(lon,Math.Log(Math.Tan(Math.PI/4+lat*Math.PI/360))*180/Math.PI);
        }
        double Scale(){return Math.Max(1,Math.Min(Math.Max(10,Width-60)/Math.Max(0.0001,maxX-minX),Math.Max(10,Height-70)/Math.Max(0.0001,maxY-minY)))*zoom;}
        PointF Screen(Coordinate p){double scale=Scale();return new PointF((float)(Width/2.0+(p.X-(minX+maxX)/2)*scale+panX),(float)(Height/2.0-(p.Y-(minY+maxY)/2)*scale+panY));}
        GraphicsPath PathFor(Shape s){var path=new GraphicsPath(FillMode.Alternate);foreach(var ring in s.Rings)path.AddPolygon(ring.Select(Screen).ToArray());return path;}
        public void ResetView(){zoom=1;panX=panY=0;Invalidate();}
        protected override void OnPaint(PaintEventArgs e) {
            base.OnPaint(e);var g=e.Graphics;g.SmoothingMode=SmoothingMode.AntiAlias;
            if(shapes.Count==0){g.DrawString("조회 후 경계가 여기에 표시됩니다.\n휠: 확대 · 드래그: 이동 · 클릭: 속성",Font,Brushes.SlateGray,20,25);return;}
            using(var fill=new SolidBrush(Color.FromArgb(48,25,137,116)))using(var pen=new Pen(Color.FromArgb(25,116,101),1.5f))
            foreach(var s in shapes) {
                RectangleF rect;
                if(s.Point.HasValue){PointF p=Screen(s.Point.Value);rect=new RectangleF(p.X-5,p.Y-5,10,10);g.FillEllipse(Brushes.IndianRed,rect);}
                else using(var path=PathFor(s)){rect=path.GetBounds();g.FillPath(fill,path);g.DrawPath(pen,path);}
                if(rect.Right<0 || rect.Bottom<0 || rect.Left>Width || rect.Top>Height)continue;
                string label=s.Label.Length>48?s.Label.Substring(0,48):s.Label;
                var size=g.MeasureString(label,Font);var at=new PointF(rect.X+rect.Width/2-size.Width/2,rect.Y+rect.Height/2-size.Height/2);
                using(var bg=new SolidBrush(Color.FromArgb(210,255,255,255)))g.FillRectangle(bg,at.X,at.Y,size.Width,size.Height);
                g.DrawString(label,Font,Brushes.DarkSlateGray,at);
            }
            g.DrawString("N ↑    조회 경계 미리보기 · 배경지도 없음",Font,Brushes.SlateGray,12,10);
        }
        protected override void OnMouseWheel(MouseEventArgs e){base.OnMouseWheel(e);zoom=Math.Max(.25f,Math.Min(128,zoom*(e.Delta>0?1.25f:.8f)));Invalidate();}
        protected override void OnMouseDown(MouseEventArgs e){base.OnMouseDown(e);Focus();if(e.Button==MouseButtons.Left){drag=e.Location;dragging=true;moved=false;Capture=true;}}
        protected override void OnMouseMove(MouseEventArgs e){base.OnMouseMove(e);if(dragging){int dx=e.X-drag.X,dy=e.Y-drag.Y;if(dx!=0||dy!=0)moved=true;panX+=dx;panY+=dy;drag=e.Location;Invalidate();}}
        protected override void OnMouseUp(MouseEventArgs e){base.OnMouseUp(e);if(!dragging)return;dragging=false;Capture=false;if(moved)return;
            foreach(var s in shapes.AsEnumerable().Reverse()) {
                bool hit;
                if(s.Point.HasValue){var p=Screen(s.Point.Value);hit=Math.Abs(p.X-e.X)<10 && Math.Abs(p.Y-e.Y)<10;}
                else using(var path=PathFor(s))hit=path.IsVisible(e.Location);
                if(hit){var callback=FeatureSelected;if(callback!=null)callback(s.Properties);break;}
            }
        }
    }
}
