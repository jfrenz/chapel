use CommDiagnostics;
use Time;
use Memory;
use StringAlgo;

use BlockDist;
use VariBlockDist;
use VariBlockPolicies;

enum DistType {Block, VB_Even, VB_StaticCut}
enum TestType {Mem, Comms, Time}

config param equalizeDists  = true;
config param correctness    = false;

// Flags to control which diagnostics to take
/*config const commDiags          = true;
config const takeTimings        = true;
config const memoryUsage        = true;*/
/*
// Flags to control which distributions to test
config const testBlock          = true;
config const testVbEven         = true;
config const testVbStaticCut    = true;


*/





config const distType: DistType;
config const testType: TestType;

config const memUnit: MemUnit = MemUnit.Byte;


proc VbBenchRun(Maker, dom: domain, locs: [] locale = Locales) {
    
    const slocs = if equalizeDists then 
                      validateDistArgs(dom, locs)
                  else
                      locs;
    
    select distType {
        when DistType.Block         do _VbBenchRunSub(Maker, dom, slocs, DistType.Block);
        when DistType.VB_Even       do _VbBenchRunSub(Maker, dom, slocs, DistType.VB_Even);
        when DistType.VB_StaticCut  do _VbBenchRunSub(Maker, dom, slocs, DistType.VB_StaticCut);
    }
}


proc _VbBenchRunSub(Maker, dom: domain, locs: [] locale, param dtype: DistType) {
    if correctness then {
        _VbBenchRunCorrectness(Maker, dom, locs, dtype);
    } else {
        _VbBenchRunPerf(Maker, dom, locs, dtype);
    }
}
    
proc _VbBenchRunCorrectness(Maker, dom: domain, locs: [] locale, param dtype: DistType) {
    writeln("---------- START OF CORRECTNESS TEST: "+dtype);
    
    const dist = MakeDist(dom, locs, dtype);
    const prog = Maker(dist, true);
    
    prog.preRunInfo();
    
    const res: bool = prog.run();
    
    prog.postRunInfo();
    delete prog;
    
    const success = if res then "SUCCESS" else "FAILURE";
    writeln("---------- END OF CORRECTNESS TEST: "+dtype+": "+success);
}

proc _VbBenchRunPerf(Maker, dom: domain, locs: [] locale, param dtype: DistType) {
    var success: bool;
    var diagStr: string;
    select testType {
        when TestType.Mem do (success, diagStr) = _VbBenchRunPerfMem(Maker, dom, locs, dtype);
        when TestType.Comms do (success, diagStr) = _VbBenchRunPerfComms(Maker, dom, locs, dtype);
        when TestType.Time do (success, diagStr) = _VbBenchRunPerfTime(Maker, dom, locs, dtype);
    }
    const successStr = if success then "SUCCESS" else "FAILURE";
    diagStr += "Distribution: "+distType:string+"\n";
    diagStr += "Test: "+testType:string+"\n";
    diagStr += "Validation: "+successStr+"\n";
    writeln(diagStr);
}

proc _VbBenchRunPerfMem(Maker, dom: domain, locs: [] locale, param dtype: DistType) {
    writeln("---------- START OF MEMORY TEST: "+dtype);
    
    var diags: string;
    
    /******************************************************/
    diags += getMemUsagesStr(dtype:string+"-MEM-BEGIN", memUnit);
    /******************************************************/
    
    const dist = MakeDist(dom, locs, dtype);
    const prog = Maker(dist, false);
    
    prog.preRunInfo();
    
    /******************************************************/
    diags += getMemUsagesStr(dtype:string+"-MEM-PRERUN", memUnit);
    /******************************************************/
    
    const res: bool = prog.run();
    
    /******************************************************/
    diags += getMemUsagesStr(dtype:string+"-MEM-POSTRUN", memUnit);
    /******************************************************/
    
    prog.postRunInfo();
    delete prog;
    
    const success = if res then "SUCCESS" else "FAILURE";
    writeln("---------- END OF MEMORY TEST: "+dtype+": "+success);
    
    return (res, diags);
}

proc _VbBenchRunPerfComms(Maker, dom: domain, locs: [] locale, param dtype: DistType) {
    writeln("---------- START OF COMMS TEST: "+dtype);
    
    var diags: string;
    
    /******************************************************/
    resetCommDiagnostics();
    startCommDiagnostics();
    /******************************************************/
    
    const dist = MakeDist(dom, locs, dtype);
    const prog = Maker(dist, false);
    
    /******************************************************/
    stopCommDiagnostics();
    const initComms = getCommDiagnostics();
    resetCommDiagnostics();
    
    prog.preRunInfo();
    
    startCommDiagnostics();
    /******************************************************/
    
    const res: bool = prog.run();
    
    /******************************************************/
    stopCommDiagnostics();
    const runComms = getCommDiagnostics();
    diags += formatCommDiags(initComms, dtype:string+"-COMMS-INIT");
    diags += formatCommDiags(runComms, dtype:string+"-COMMS-RUN");
    /******************************************************/
    
    prog.postRunInfo();
    delete prog;
    
    const success = if res then "SUCCESS" else "FAILURE";
    writeln("---------- END OF COMMS TEST: "+dtype+": "+success);
    
    return (res, diags);
}

proc _VbBenchRunPerfTime(Maker, dom: domain, locs: [] locale, param dtype: DistType) {
    writeln("---------- START OF TIME TEST: "+dtype);
    
    var diags: string;
    
    /******************************************************/
    const timerInit: Timer;
    const timerRun: Timer;
    timerInit.start();
    /******************************************************/
    
    const dist = MakeDist(dom, locs, dtype);
    const prog = Maker(dist, false);
    
    /******************************************************/
    timerInit.stop();
    
    prog.preRunInfo();
    
    timerRun.start();
    /******************************************************/
    
    const res: bool = prog.run();
    
    /******************************************************/
    timerRun.stop();
    diags += dtype:string+"-TIME-INIT: "+timerInit.elapsed():string+" s\n";
    diags += dtype:string+"-TIME-RUN: "+timerRun.elapsed():string+" s\n";
    /******************************************************/
    
    prog.postRunInfo();
    delete prog;
    
    const success = if res then "SUCCESS" else "FAILURE";
    writeln("---------- END OF TIME TEST: "+dtype+": "+success);
    
    return (res, diags);
}


proc MakeDist(dom: domain, locs: [?locsDom] = Locales, param dtype: DistType)
    where dtype == DistType.Block 
{
    const slocs = validateDistArgs(dom, locs);
    return new dmap(new Block(boundingBox=dom, slocs));
}

proc MakeDist(dom: domain, locs: [?locsDom] = Locales, param dtype: DistType)
    where dtype == DistType.VB_Even 
{
    const slocs = validateDistArgs(dom, locs);
    const P = new EvenPolicy(dom=dom, targetLocales=slocs);
    return new dmap(new VariBlock(P));
}

proc MakeDist(dom: domain, locs: [?locsDom] = Locales, param dtype: DistType)
    where dtype == DistType.VB_StaticCut 
{
    const slocs = validateDistArgs(dom, locs);
    const P = new StaticCutPolicy(dom=dom, targetLocs=slocs);
    return new dmap(new VariBlock(P));
}


proc validateDistArgs(dom: domain, locs: [?locsDom] locale) {
    if locsDom.idxType != int then {
        compilerError("idxType of locs must be int");
    }
    
    param rank = dom.rank;
    
    
    var slocsDom: domain(rank);
    var slocs: [slocsDom] locale;
    
    if dom.rank == locs.rank then {
        slocsDom = locsDom;
        slocs = locs;
    } else {
        const factors = _factor(rank, locs.numElements);
        var ranges: rank*range;
        
        for param i in 1..rank do {
            ranges(i) = 0..#factors(i);
        }
                
        slocsDom = {(...ranges)};
        slocs = reshape(locs, slocsDom);
    }
    
    for i in 1..rank do {
        const ds = dom.dim(i).size;
        const ls = slocsDom.dim(i).size;
        
        if ds < ls then {
            halt("Locs array's size ("+ls+") is larger than the domain's ("+ds+") in dimension "+i);
        }
    }
    
    return slocs;
}


enum MemUnit {Byte=0, KiB=1, MiB=2, GiB=3}

proc MemUnitConvert(val: ?fromType, from: MemUnit, to: MemUnit, type toType = uint(64)) {
    const exp: int = from:int - to:int;
    const fac: uint = (1024 ^ abs(exp)):uint;
    
    if exp > 0 then {
        return ((val:toType * fac): toType);
    } else if exp < 0 then {
        return ((val:toType / fac): toType);
    }
    
    return val: toType;
}

proc MemUnitToString(unit: MemUnit): string {
    select unit {
        when MemUnit.Byte do return "B";
        when MemUnit.KiB do return "KiB";
        when MemUnit.MiB do return "MiB";
        when MemUnit.GiB do return "GiB";
    }
    halt("Unknown MemUnit value");
}

proc getMemUsagesStr(prefix: string = "", unit: MemUnit = MemUnit.Byte): string {
    var str: string;
    var usageOnLocale: uint(64);
    var suffix: string;
    
    for loc in Locales do on loc {
        suffix = MemUnitToString(unit);
        usageOnLocale = memoryUsed();
        usageOnLocale = MemUnitConvert(usageOnLocale, MemUnit.Byte, unit);
        str += prefix+"-"+loc:string+": "+usageOnLocale+" "+suffix+"\n";
    }
    
    return str;
}

proc formatCommDiags(diags, prefix): string {
    var ret: string;
    
    for loc in Locales do {
        const d = diags(loc.id);
        const pre =  prefix+"-"+loc:string+"-";
        
        ret += pre+"get: "+d.get+"\n";
        ret += pre+"get_nb: "+d.get_nb+"\n";
        ret += pre+"put: "+d.put+"\n";
        ret += pre+"put_nb: "+d.put_nb+"\n";
        ret += pre+"test_nb: "+d.test_nb+"\n";
        ret += pre+"wait_nb: "+d.wait_nb+"\n";
        ret += pre+"try_nb: "+d.try_nb+"\n";
        ret += pre+"fork: "+d.fork+"\n";
        ret += pre+"fork_fast: "+d.fork_fast+"\n";
        ret += pre+"fork_nb: "+d.fork_nb+"\n";
        
        //ret += prefix+": "+loc:string+": "+d:string+"\n";
    }
    
    return ret;
}


proc +(a:commDiagnostics, b:commDiagnostics): commDiagnostics {
    var r: commDiagnostics;
    r.get = a.get + b.get;
    r.get_nb = a.get_nb + b.get_nb;
    r.put = a.put + b.put;
    r.put_nb = a.put_nb + b.put_nb;
    r.test_nb = a.test_nb + b.test_nb;
    r.wait_nb = a.wait_nb + b.wait_nb;
    r.try_nb = a.try_nb + b.try_nb;
    r.fork = a.fork + b.fork;
    r.fork_fast = a.fork_fast + b.fork_fast;
    r.fork_nb = a.fork_nb + b.fork_nb;
    return r;
}

