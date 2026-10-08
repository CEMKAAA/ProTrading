"""Bundle canonical EA implementations without changing their calculation logic.

Only the generated connection runtime uses this bundle. The four production
sources remain untouched. Artifacts are overwritten in one bounded directory.
"""
from pathlib import Path
import hashlib
import json
import re

RUNTIME = {
 "targetR": ("double", 1.0, "Geometry"), "balance": ("double", 0.0, "Risk"),
 "independent": ("bool", False, "Positions"), "maxOpen": ("int", 10, "Positions"),
 "reverseExit": ("bool", False, "Positions"), "reverseWaitMinutes": ("int", 0, "Positions"),
 "inversion": ("bool", False, "Geometry"), "inverseMaxCostPct": ("double", 100.0, "Geometry"),
 "advancedAudit": ("bool", True, "Audit"), "nextDayExit": ("bool", True, "Positions"),
 "nasGate": ("int", 0, "NAS"), "nasExit": ("int", 0, "NAS"),
 "nasStateVolume": ("bool", False, "NAS"), "nasFlowVolume": ("bool", False, "NAS"),
 "nasStateMultiplier": ("double", 1.0, "NAS"), "nasFlowMultiplier": ("double", 1.0, "NAS"),
 "nasSensitivity": ("int", 4, "NAS"), "nasWaitMinutes": ("int", 0, "NAS"),
 "nasAgeMinutes": ("int", 120, "NAS"), "timeMatrixEnabled": ("bool", False, "Time Matrix"),
 "entryPreset": ("int", 0, "Entry / Execution"),
}

def runtime_targets(family):
    common = {"balance":"g_nativeRiskBalance", "timeMatrixEnabled":"g_tcalEnabled"}
    if family == "sol":
        common.update(dict(zip(
          ["targetR","independent","maxOpen","reverseExit","reverseWaitMinutes","inversion","inverseMaxCostPct",
           "nasGate","nasExit","nasStateVolume","nasFlowVolume","nasStateMultiplier","nasFlowMultiplier","nasSensitivity","nasWaitMinutes","nasAgeMinutes"],
          ["g_customTargetR","g_lnNas.independent","g_lnNas.maxSameOpen","g_lnNas.reverseExit","g_lnNas.reverseWaitMinutes","g_invertMode","g_inverseMaxGapPct",
           "g_lnNas.gate","g_lnNas.exitMode","g_lnNas.stateVolume","g_lnNas.flowVolume","g_lnNas.stateMultiplier","g_lnNas.flowMultiplier","g_lnNas.sensitivity","g_lnNas.waitMinutes","g_lnNas.entryAgeMinutes"])))
    else:
        common.update(dict(zip(
          ["targetR","inversion","inverseMaxCostPct","advancedAudit","nasStateVolume","nasFlowVolume","nasStateMultiplier","nasFlowMultiplier","nasSensitivity","nasWaitMinutes","nasAgeMinutes"],
          ["g_rtCustomR","g_rtInvertMode","g_rtAdvancedReverseMaxCostPct","g_rtAdvancedAuditEngine","g_rtNasVolumeFilter","g_rtNasFlowVolumeFilter","g_rtNasVolumeMultiplier","g_rtNasFlowVolumeMultiplier","g_rtNasSensitivity","g_rtNasOppositeExitWaitMinutes","g_rtNasActiveSignalLookbackMinutes"])))
        position = ["g_orbPositions.independent","g_orbPositions.maxSameOpen","g_orbPositions.reverse","g_orbPositions.waitMinutes"] if family=="orb" else ["g_maIndependent","g_maMaxConsecutive","g_maReverseExit","g_maReverseWait"]
        common.update(dict(zip(["independent","maxOpen","reverseExit","reverseWaitMinutes"],position)))
        if family == "orb": common["nextDayExit"]="g_orbPositions.nextDay"
        if family == "orb": common["inverseMaxCostPct"]="g_rtInverseMaxGapPct"
        if family == "entrylab": common["entryPreset"]=""
    return common

def group_for(name):
    for pattern, group in [(r"Nas","NAS"),(r"Regime|OrbRf","Regimes"),(r"Of|OrderFlow","Order Flow"),
      (r"Clock|Gmt|Ny|Session|Utc","Session / Timezone"),(r"Risk|Lot|Balance|Drawdown|LossLimit","Risk"),
      (r"Pip|Sl|Tp|Target|Half|BE|Invert","Geometry"),(r"Backtest|Historical|Audit","Audit"),
      (r"Vol|Atr|Fvg|Disp|Smt|Asia|Sweep|Irl|DayFilter","Filters")]:
        if re.search(pattern,name): return group
    return "Entry / Execution"

def exposed(name):
    return not re.search(r"License|Bridge|Channel|Publish|TdCalendar|AuditCsv|Tester|Validation|Magic|Probe|LogOn|LogEvery|Show|DrawHistorical|File|Folder|Prefix|NativeTrade|EaEnabled|Ftmo|OnlyMode|AuditTrade|AuditPosition|AuditHistorical|SignalFile|TradeCsv",name,re.I)

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "IndicatorCodeExamples"
OUT = SOURCE / "universal" / "generated"
FAMILIES = {
    "orb": "orb/OrbUltimateEA_StrategyLibrary.mq5",
    "macross": "macrossover_orb/MaCrossOverOrbEA.mq5",
    "sol": "SolAdvanced/LiqNarrativeSol_Advanced.mq5",
    "entrylab": "entry_engine_lab/EntryEngineLabEA.mq5",
}
LEX = re.compile(r'//[^\n]*|/\*[\s\S]*?\*/|"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'')

def masked(text):
    return LEX.sub(lambda m: re.sub(r"[^\n]", " ", m[0]), text)

def flatten(path, seen, manifest):
    path = path.resolve()
    if not path.is_relative_to(SOURCE):
        raise ValueError(f"External project dependency: {path}")
    if path in seen:
        return ""
    seen.add(path)
    text = path.read_text(encoding="utf-8-sig")
    manifest[str(path.relative_to(SOURCE))] = hashlib.sha256(path.read_bytes()).hexdigest()
    return re.sub(r'^\s*#include\s+"([^"]+)"[^\n]*',
                  lambda m: flatten(path.parent / m[1], seen, manifest), text, flags=re.M)

def symbols(text):
    clean = masked(text)
    names = set(re.findall(r"^\s*#define\s+(\w+)", clean, re.M))
    names.update(re.findall(r"^\s*#define\s+\w+\s+([A-Za-z_]\w*)\s*$", clean, re.M))
    names.update(re.findall(r"\b(?:struct|class|enum)\s+(\w+)", clean))
    names.update(re.findall(r"\b(?:input|sinput)\s+\w+\s+(\w+)\s*=", clean))
    names.update(re.findall(r"\bg_\w+\b", clean))
    for m in re.finditer(r"\benum(?:\s+\w+)?\s*\{([^}]+)\}", clean):
        names.update(re.findall(r"(?:^|,)\s*(\w+)", m[1]))
    # Top-level declarations only: do not rename SDK member functions/fields.
    clean = re.sub(r"^\s*#.*", "", clean, flags=re.M)
    depth = 0
    start = 0
    for i, c in enumerate(clean):
        if c == "{":
            if depth == 0:
                header = clean[start:i].strip()
                fn = re.search(r"\b(\w+)\s*\([^;{}]*\)\s*(?:const)?$", header)
                if fn:
                    names.add(fn[1])
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                start = i + 1
        elif c == ";" and depth == 0:
            statement = clean[start:i].strip()
            # Strip modifiers, then a type, then collect comma-separated names.
            statement = re.sub(r"^(?:(?:input|sinput|const|static|extern)\s+)+", "", statement)
            declaration = re.match(r"\w+\s+(.+)$", statement, re.S)
            if declaration:
                tail = declaration[1]
                fn = re.match(r"(\w+)\s*\(", tail)
                if fn:
                    names.add(fn[1])
                else:
                    # Initializer commas cannot introduce another variable.
                    tail = re.sub(r"\{[^}]*\}|\([^)]*\)", "", tail)
                    names.update(re.findall(r"(?:^|,)\s*(\w+)\s*(?:\[|=|,|$)", tail))
            start = i + 1
    return names

def rewrite(text, names, prefix):
    pieces = []
    end = 0
    for m in LEX.finditer(text):
        pieces.append(re.sub(r"\b\w+\b", lambda t: prefix + t[0] if t[0] in names else t[0], text[end:m.start()]))
        pieces.append(m[0])
        end = m.end()
    pieces.append(re.sub(r"\b\w+\b", lambda t: prefix + t[0] if t[0] in names else t[0], text[end:]))
    return "".join(pieces)

def main():
    OUT.mkdir(parents=True, exist_ok=True)
    catalog = {}
    manifest = {}
    sdk = set()
    for family, source in FAMILIES.items():
        text = flatten(SOURCE / source, set(), manifest)
        sdk.update(re.findall(r"^\s*#include\s+<([^>]+)>", text, re.M))
        enums = {}
        for m in re.finditer(r"\benum\s+(\w+)\s*\{([^}]+)\}", masked(text)):
            value = -1
            opts = []
            for item in m[2].split(","):
                match = re.match(r"\s*(\w+)\s*(?:=\s*(-?\d+))?", item)
                if match:
                    value = int(match[2]) if match[2] else value + 1
                    opts.append({"label": match[1], "value": value})
            enums[m[1]] = opts
        enums["ENUM_TIMEFRAMES"] = [{"label": k, "value": v} for k,v in
            [("CURRENT",0)]+[("M"+str(n),n) for n in (1,2,3,4,5,6,10,12,15,20,30)]
            +[("H"+str(n),16384+n) for n in (1,2,3,4,6,8,12)]+[("D1",16408),("W1",32769),("MN1",49153)]]
        inputs = []
        for m in re.finditer(r'^\s*input\s+(\w+)\s+(\w+)\s*=\s*([^;]+);[^\n]*', text, re.M):
            type_, name, default = m[1], m[2], m[3].strip()
            inputs.append({"key":name, "type":type_, "defaultMql":default,
                           "options":enums.get(type_, []), "description":m[0].split("//",1)[-1].strip() if "//" in m[0] else ""})
        enum_values={o["label"]:o["value"] for opts in enums.values() for o in opts}
        enum_values.update({"PERIOD_"+o["label"]:o["value"] for o in enums["ENUM_TIMEFRAMES"]})
        enum_values.update({"PRICE_CLOSE":0,"PRICE_OPEN":1,"PRICE_HIGH":2,"PRICE_LOW":3,"MODE_EMA":1,"MODE_SMA":0})
        public=[]
        for item in inputs:
            default=item["defaultMql"]
            if default in ("true","false"): value=default=="true"
            elif default.startswith('"'): value=json.loads(default)
            elif default in enum_values: value=enum_values[default]
            else:
                try: value=float(default) if "." in default else int(default)
                except ValueError:
                    if exposed(item["key"]): raise ValueError(f"Unknown default {family}: {item}")
                    value=None
            if family == "sol" and item["key"] == "InpDefaultHtf":
                # Sol already builds H1.5 from closed M30 bars; it is not an MT5 enum.
                item["options"] = [*item["options"], {"label": "H1.5", "value": 90}]
            if exposed(item["key"]):
                public.append({**item,"default":value,"group":group_for(item["key"])})
        rt=runtime_targets(family)
        if family!="sol": rt.update({"nasGate":"", "nasExit":""})
        catalog[family]={"inputs":public,"runtime":[{"key":k,"type":v[0],"default":v[1],"group":v[2]} for k,v in RUNTIME.items() if k in rt]}
        names = symbols(text)
        text = re.sub(r'^\s*#(?:include|property)[^\n]*', "", text, flags=re.M)
        text = re.sub(r'^\s*input\s+group[^\n]*', "", text, flags=re.M)
        text = re.sub(r"\binput\s+", "", text)
        # Skip automatic OnInit research; the web alone starts the audit.
        start=text.index("int OnInit(")
        end=text.index("void OnDeinit(",start)
        init=text[start:end]
        init=re.sub(r"\b(?:RecalculateHistoricalStats|DrawHistoricalSignals|QueueHistoricalRedraw)\([^;]*\);", "", init)
        text=text[:start]+init+text[end:]
        # Customer commands cannot inherit house presets or local Lab selections.
        for name in ("OrbStrategyPresetRestore","LabRestoreActive"):
            match=re.search(r"\b(void|bool)\s+"+name+r"\s*\([^)]*\)\s*\{",text)
            if not match: continue
            clean=masked(text);depth=1;end=match.end()
            while depth:
                if clean[end]=="{":depth+=1
                if clean[end]=="}":depth-=1
                end+=1
            text=text[:match.end()]+(" return false; " if match[1]=="bool" else "\n")+text[end-1:]
        # Input restoration is local-dashboard behavior, not web configuration.
        for match in reversed(list(re.finditer(r"\b(?:void|bool)\s+(LoadRuntime\w+|MaIndependentInit)\s*\([^)]*\)\s*\{",text))):
            clean=masked(text);depth=1;end=match.end()
            while depth:
                if clean[end]=="{":depth+=1
                if clean[end]=="}":depth-=1
                end+=1
            text=text[:match.end()]+re.sub(r"\bGlobalVariableCheck\b","UcLocalSettingExists",text[match.end():end-1])+text[end-1:]
        for realm in ("audit", "live"):
            prefix=("" if realm=="audit" else "live_")+family+"_"
            bundle=rewrite(text,names,prefix)
            bundle=re.sub(r"\bCTrade\b","UcTrade",bundle)
            # Stable installation ownership replaces ChartID-scoped ownership,
            # without changing any signal, geometry or historical fill formula.
            match=re.search(r"\blong\s+"+prefix+r"RuntimeMagic\s*\(\)\s*\{",bundle)
            if match:
                clean=masked(bundle);depth=1;end=match.end()
                while depth:
                    if clean[end]=="{":depth+=1
                    if clean[end]=="}":depth-=1
                    end+=1
                bundle=bundle[:match.end()]+f' return UcMagic("{family}")+{0 if realm=="live" else 3000000000}; '+bundle[end-1:]
            if realm=="audit": bundle=re.sub(r"\bTimeCurrent\b","UcAuditNow",bundle)
            bundle=re.sub(r"\bObjectCreate\b","UcObjectCreate",bundle)
            bundle=re.sub(r"\bObjectDelete\b","UcObjectDelete",bundle)
            bundle=re.sub(r"\bObjectsDeleteAll\b","UcObjectsDeleteAll",bundle)
            bundle=re.sub(r"\bGlobalVariable(Check|Get|Set|Del|SetOnCondition|Temp)\b",r"UcVariable\1",bundle)
            (OUT/(prefix[:-1]+".mqh")).write_text(bundle,encoding="utf-8")
        setters=[f"void UcReset_{family}(bool live)","{"]
        for item in inputs:
            value=rewrite(item["defaultMql"],names,family+"_")
            value_live=rewrite(item["defaultMql"],names,"live_"+family+"_")
            setters.append(f' if(live)live_{family}_{item["key"]}={value_live};else {family}_{item["key"]}={value};')
        setters+= ["}",f"bool UcSetting_{family}(string key,string value,bool live)","{"]
        for item in public:
            typ=item["type"]
            conv="value" if typ=="string" else '(value=="true")' if typ=="bool" else "StringToDouble(value)" if typ=="double" else "(int)StringToInteger(value)" if typ=="int" else "StringToInteger(value)"
            cast="" if typ in ("string","bool","double","long","int") else f'({family+"_" if typ in names else ""}{typ})'
            livecast=cast.replace(family+"_","live_"+family+"_")
            setters.append(f' if(key=="i.{item["key"]}"){{if(live)live_{family}_{item["key"]}={livecast}{conv};else {family}_{item["key"]}={cast}{conv};return true;}}')
        for key,target in rt.items():
            if not target: continue
            typ=RUNTIME[key][0]
            conv='value=="true"' if typ=="bool" else "StringToDouble(value)" if typ=="double" else "(int)StringToInteger(value)"
            setters.append(f' if(key=="r.{key}"){{if(live)live_{family}_{target}={conv};else {family}_{target}={conv};return true;}}')
        if family!="sol":
            for key,a,b in [("nasGate","g_rtNasConfirmation","g_rtNasStateGate"),("nasExit","g_rtNasExitOnOppositeSignal","g_rtNasAdditionalExit")]:
                setters.append(f' if(key=="r.{key}"){{if(live){{live_{family}_{a}=value=="1";live_{family}_{b}=value=="2";}}else{{{family}_{a}=value=="1";{family}_{b}=value=="2";}}return true;}}')
        setters.append(' return false;\n}')
        if family=="entrylab":
            setters[-1]=' if(key=="r.entryPreset")return true;\n return false;\n}'
        (OUT/(family+"_settings.mqh")).write_text("\n".join(setters),encoding="utf-8")
        print(f"{family}: {len(names)} isolated symbols / {len(inputs)} inputs")
    (OUT / "sdk.mqh").write_text("\n".join(f"#include <{s}>" for s in sorted(sdk)), encoding="ascii")
    (OUT / "catalog.json").write_text(json.dumps(catalog, indent=2), encoding="utf-8")
    (ROOT/"web-mvp/lib/ea-controls.json").write_text(json.dumps(catalog,indent=2),encoding="utf-8")
    (OUT / "source-manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")

if __name__ == "__main__":
    main()
