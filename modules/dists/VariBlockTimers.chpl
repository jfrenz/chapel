/*
 * Copyright 2004-2015 Cray Inc.
 * Other additional copyright holders may be indicated within.
 * 
 * The entirety of this work is licensed under the Apache License,
 * Version 2.0 (the "License"); you may not use this file except
 * in compliance with the License.
 * 
 * You may obtain a copy of the License at
 * 
 *     http://www.apache.org/licenses/LICENSE-2.0
 * 
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

// Abstract base classess for timers
class VB_TimerBase_Dmap {
    proc getNewDmapTimer(): VB_TimerBase_Dmap {
        halt("This should be abstract base class");
    }
    
    proc getDomainTimer(): VB_TimerBase_Domain {
        halt("This should be abstract base class");
    }
}

class VB_TimerBase_Domain {
    proc timeNext(): bool {
        halt("This should be abstract base class");
    }
    
    proc processTimings(timings: [?D] real) {
        for i in D do {
            processTiming(i, timings(i));
        }
    }
    
    proc processTiming(locid:int, time: real) {
        halt("This should be abstract base class");
    }
}


// Times every n:th operation on domains
// TODO: Replace A with an associative array. Due to a bug in the compiler
// I wasn't able to do that yet.
class NthDomTimer: VB_TimerBase_Dmap {
    const N: int;
    const D = LocaleSpace;
    var A: [LocaleSpace] real;
    
    proc NthDomTimer(N:int = 11) {
        if N < 1 then {
            halt("N must be larger than or equal to one");
        }
        this.N = N;
    }
    
    proc getNewDmapTimer(): VB_TimerBase_Dmap {
        return this:VB_TimerBase_Dmap;
    }
    
    proc getDomainTimer(): VB_TimerBase_Domain {
        return new NthDomTimer_dom(N, this);
    }
    
    proc processTiming(locid:int, time: real) {
        A[locid] += time;
    }
    
    proc dump() {
        writeln(" * Timing results:");
        for idx in D do {
            writeln("Locale "+idx+": "+A(idx)+" sec.");
        }
        writeln();
    }
    
}

class NthDomTimer_dom: VB_TimerBase_Domain {
    const parent: NthDomTimer;
    const N: int;
    var n: int = 0;
    
    proc NthDomTimer_dom(N: int, parent: NthDomTimer) {
        this.parent = parent;
        this.N = N;
    }
    
    proc timeNext(): bool {
        var _t = false;
        
        if n == 0 then {
            _t = true;
            n = N;
        }
        
        n -= 1;
        
        return _t;
    }
    
    proc processTiming(locid:int, time: real) {
        parent.processTiming(locid, time);
    }
}


