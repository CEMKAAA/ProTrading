#ifndef LIQ_DASHBOARD_FIT_MQH
#define LIQ_DASHBOARD_FIT_MQH
// Navigate the logical canvas instead of shrinking fonts to fit its height.
int g_liqDashScroll=0,g_liqDashHorizontal=0;
int LiqViewportHeight(){return (int)MathMax(100,ChartGetInteger(0,CHART_HEIGHT_IN_PIXELS)-54);}
int LiqViewportWidth(){return (int)MathMax(100,MathMin(760,ChartGetInteger(0,CHART_WIDTH_IN_PIXELS)-16));}
double LiqDashboardScale(){return 1.0;}
void LiqFitClamp()
{
   g_liqDashScroll=MathMax(0,MathMin(g_liqDashScroll,LIQ_DASH_LOGICAL_HEIGHT-LiqViewportHeight()));
   g_liqDashHorizontal=MathMax(0,MathMin(g_liqDashHorizontal,760-LiqViewportWidth()));
}
void LiqFitPoint(int &x,int &y)
{
   LiqFitClamp();x=8+x-InpDashboardX-g_liqDashHorizontal;y=42+y-InpDashboardY-g_liqDashScroll;
   if(y<42||y+20>42+LiqViewportHeight()||x<8||x>=8+LiqViewportWidth()){x=30000;y=30000;}
}
void LiqFitBox(int &x,int &y,int &w,int &h)
{
   LiqFitClamp();x=8+x-InpDashboardX-g_liqDashHorizontal;y=42+y-InpDashboardY-g_liqDashScroll;
   if(h>40)
   {
      int right=MathMin(x+w,8+LiqViewportWidth()),bottom=MathMin(y+h,42+LiqViewportHeight());
      x=MathMax(8,x);y=MathMax(42,y);w=MathMax(1,right-x);h=MathMax(1,bottom-y);
      if(right<=x||bottom<=y){x=30000;y=30000;}
   }
   else if(y<42||y+h>42+LiqViewportHeight()||x<8||x+w>8+LiqViewportWidth()){x=30000;y=30000;}
}
int LiqFitFont(int size){return MathMax(9,size);}
#endif
