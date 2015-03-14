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

// Since the policy VariBlock excepts is a generic, there is no base class.


class EvenPolicy {
    
    param rank;
    type idxType;
    
    type targetLocsDomType = domain(rank, idxType);
    
    type indexerType = EvenPolicyIndexer(rank, idxType);
    
    const dom: domain(rank);
    
    const targetLocsOriginalDomain: domain(1);
    const targetLocsOriginal: [targetLocsOriginalDomain] locale;
    
    var targetLocsDom: targetLocsDomType;
    
    proc EvenPolicy(dom: domain, targetLocales: [] locale = Locales, param rank = dom.rank, type idxType = dom.idxType) {
        if rank != dom.rank then {
            compilerError("Ranks don't match");
        }
        
        if idxType != dom.idxType then {
            compilerError("IdxTypes don't match");
        }
        
        
        if targetLocales.size < 1 then {
            halt("At least one locale needed to distribute...");
        }
        
        if targetLocales.size > dom.size then {
            halt("Domain to be distributed needs to have at least as many indices as there are locales across which to distribute.");
        }
        
        
        this.dom = dom;
        
        this.targetLocsOriginalDomain = {0..#targetLocales.size};
        this.targetLocsOriginal = reshape(targetLocales, targetLocsOriginalDomain);
    }
    
    proc setupArrays(ref targetLocDom: targetLocsDomType, targetLocArr: [targetLocDom] locale) {
        if rank != 1 && targetLocsOriginal.rank == 1 {
            const factors = _factor(rank, targetLocsOriginal.numElements);
            var ranges: rank*range;
            for param i in 1..rank do
            ranges(i) = 0..#factors(i);
            targetLocDom = {(...ranges)};
            targetLocArr = reshape(targetLocsOriginal, targetLocDom);
            targetLocsDom = targetLocDom;
        } else {
            if targetLocsOriginal.rank != rank then
                compilerError("specified target array of locales must equal 1 or distribution rank");
            var ranges: rank*range;
            for param i in 1..rank do
            ranges(i) = 0..#targetLocsOriginal.domain.dim(i).length;
            targetLocDom = {(...ranges)};
            targetLocArr = targetLocsOriginal;
            targetLocsDom = targetLocDom;
        }
    }
    
    proc computeChunk(locid) {
        const boundingBox = dom.dims();
        const targetLocBox = targetLocsDom.dims();
        if rank == 1 {
            const lo = boundingBox(1).low;
            const hi = boundingBox(1).high;
            const numelems = hi - lo + 1;
            const numlocs = targetLocBox(1).length;
            const (blo, bhi) = _computeBlock(numelems, numlocs, locid,
                                            max(idxType), min(idxType), lo);
            return {blo..bhi};
        } else {
            var inds: rank*range(idxType);
            for param i in 1..rank {
            const lo = boundingBox(i).low;
            const hi = boundingBox(i).high;
            const numelems = hi - lo + 1;
            const numlocs = targetLocBox(i).length;
            const (blo, bhi) = _computeBlock(numelems, numlocs, locid(i),
                                            max(idxType), min(idxType), lo);
            inds(i) = blo..bhi;
            }
            return {(...inds)};
        }
    }
    
    proc makeIndexer() {
        return new EvenPolicyIndexer(dom, targetLocsDom);
    }
    
}

class EvenPolicyIndexer {
    param rank;
    type idxType;
    
    const dom: domain(rank);
    const targetLocDom: domain(rank);
    
    proc EvenPolicyIndexer(dom: domain, targetLocDom: domain, param rank = dom.rank, type idxType = dom.idxType) {
        if dom.rank != rank then {
            compilerError("Rank and rank of domain don't match");
        }
        
        if idxType != dom.idxType then {
            compilerError("IdxTypes don't match");
        }
        
        
        this.dom = dom;
        this.targetLocDom = targetLocDom;
    }
    
    proc targetLocIdx(ind: rank*idxType) {
        var result: rank*int;
        for param i in 1..rank do
            result(i) = max(0, min((targetLocDom.dim(i).length-1):int,
                                (((ind(i) - dom.dim(i).low) *
                                    targetLocDom.dim(i).length:idxType) /
                                    dom.dim(i).length):int));
            
        return if rank == 1 then result(1) else result;
    }
}