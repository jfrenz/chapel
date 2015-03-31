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

module StringAlgo {

enum FindAlgorithm { BruteForce };

proc find(str: string, needle: string, start: int = 1, end: int = str.length,
           param right = false,
           param algorithm:FindAlgorithm = FindAlgorithm.BruteForce): int {
    
    if boundsChecking then {
        if start < 1 || start > str.length then
            halt("start value out of bounds");
        if end < 1 || end > str.length then
            halt("end value out of bounds");
        if end < start then
            halt("start value must be smaller than or equal to end value");
    }
    
    return _find(str, needle, start, end, right, algorithm);
}

proc _find(str: string, needle: string, start: int = 1, end: int = str.length,
            param right, param algorithm:FindAlgorithm): int
            where algorithm == FindAlgorithm.BruteForce {
    
    if str.length == 0 then
        return 0;
    
    const R =   if !right then
                    start..(end - needle.length + 1)
                else
                    start..(end - needle.length + 1) by -1;
    
    for i in R do {
        if str.substring(i..#needle.length) == needle then
            return i;
    }
    
    return 0;
}

inline proc _find_of(str: string, tokens:string, R: range, param first:bool, param not:bool): int {
    if str.length <= 0 then {
        return 0;
    }
    
    if R.length <= 0 then {
        return 0;
    }
    
    if boundsChecking {
        const stringRange = 1..#str.length;
        if ! stringRange.member(R) then {
            halt("R must be subrange of the range of str");
        }
    }
    
    const rn = R by (if first then 1 else -1);
    
    for i in rn do {
        if !contains(tokens, str.substring(i)) == not then
            return i;
    }
    
    return 0;
}

proc find_first_of(str: string, tokens: string, R: range = 1..#str.length): int {
    return _find_of(str, tokens, R, first=true, not=false);
}

proc find_last_of(str: string, tokens: string, R: range = 1..#str.length): int {
    return _find_of(str, tokens, R, first=false, not=false);
}

proc find_first_not_of(str: string, tokens: string, R: range = 1..#str.length): int {
    return _find_of(str, tokens, R, first=true, not=true);
}

proc find_last_not_of(str: string, tokens: string, R: range = 1..#str.length): int {
    return _find_of(str, tokens, R, first=false, not=true);
}

proc contains(str:string, c: string): bool {
    if boundsChecking then {
        if c.length != 1 then
            halt("c must have length of 1");
    }
    
    return find(str, c, algorithm=FindAlgorithm.BruteForce) != 0;
}

proc tokenize(str: string, delimiters: string, count: int = -1, type castTo = string, param ignoreEmpty: bool = true) {
    var retDom: domain(1);
    var ret: [retDom] castTo;
    
    for token in tokenizeIter(str, delimiters, count, castTo, ignoreEmpty) do {
        retDom = 0..#(retDom.size + 1);
        ret(retDom.high) = token;
    }
    
    return ret;
}

iter tokenizeIter(str: string, delimiters: string, in count: int = -1, type castTo = string, param ignoreEmpty: bool = true): castTo {
    
    var start:int = 1;

    for i in 1..#str.length do {
    
        if count == 1 then {
            if ignoreEmpty then
                yield trim(str.substring(start..str.length), delimiters, leading=true, trailing=false):castTo;
            else
                yield str.substring(start..str.length):castTo;
                
            return;
        }
    
        const c = str.substring(i);
        if contains(delimiters, c) then {
            
            if start != i then {
                yield str.substring(start..(i-1)):castTo;
                count -= 1;
            } else if !ignoreEmpty then {
                yield "":castTo;
                count -= 1;
            }
            start = i+1;
        }
    }
    
    if start <= str.length then
        yield str.substring(start..str.length):castTo;
    else if !ignoreEmpty then
        yield "":castTo;
}


proc trim(str: string, m: string = "\t\n\f\r\v ", leading = true, trailing = true): string {

    var ret:string;
    
    if leading && trailing then {
        
        const start = find_first_not_of(str, m);
        
        if start == 0 then {
            ret = "";
        } else {
            const end = find_last_not_of(str, m);
           //const end = str.length;
            ret = str.substring(start..end);
        }
    } else if leading {
        
        const start = find_first_not_of(str, m);
        
        if start == 0 then {
            ret = "";
        } else {
            ret = str.substring(start..str.length);
        }
    } else if trailing {
        
        const end = find_last_not_of(str, m);
        
        if end == 0 then {
            ret = "";
        } else {
            ret = str.substring(1..end);
        }
    } else {
        ret = str;
    }
    
    return ret;
}

}
