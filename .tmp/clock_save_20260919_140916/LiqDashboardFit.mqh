#ifndef LIQ_DASHBOARD_FIT_MQH
#define LIQ_DASHBOARD_FIT_MQH
double LiqDashboardScale()
{
   long w=ChartGetInteger(0,CHART_WIDTH_IN_PIXELS),h=ChartGetInteger(0,CHART_HEIGHT_IN_PIXELS);
   if(w<=0||h<=0)return 1.0;
   return MathMax(0.1,MathMin(1.0,MathMin((w-16.0)/760.0,(h-16.0)/LIQ_DASH_LOGICAL_HEIGHT)));
}
void LiqFitPoint(int &x,int &y)
{
   double scale=LiqDashboardScale();
   int left=(int)MathMax(0,MathMin(InpDashboardX,ChartGetInteger(0,CHART_WIDTH_IN_PIXELS)-760*scale-8));
   int top=(int)MathMax(0,MathMin(InpDashboardY,ChartGetInteger(0,CHART_HEIGHT_IN_PIXELS)-LIQ_DASH_LOGICAL_HEIGHT*scale-8));
   x=left+(int)MathRound((x-InpDashboardX)*scale);
   y=top+(int)MathRound((y-InpDashboardY)*scale);
}
void LiqFitBox(int &x,int &y,int &w,int &h)
{
   LiqFitPoint(x,y);double scale=LiqDashboardScale();
   w=(int)MathMax(1,MathRound(w*scale));h=(int)MathMax(1,MathRound(h*scale));
}
int LiqFitFont(int size){return (int)MathMax(5,MathRound(size*LiqDashboardScale()));}
#endif
