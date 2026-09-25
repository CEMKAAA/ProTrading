#property strict
int OnInit(){Print("ASYNC_MINIMAL_ONINIT"); EventChartCustom(0, 71, 9, 0.0, ""); return INIT_SUCCEEDED;}
void OnChartEvent(const int id,const long &l,const double &d,const string &s){if(id==CHARTEVENT_CUSTOM+71) Print("ASYNC_MINIMAL_EVENT ",l);}
