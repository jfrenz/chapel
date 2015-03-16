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
use Search;

proc computePartitioning(const in R: range, const ref indexPartitions: [] real )
    where indexPartitions.rank == 1 && indexPartitions.idxType == int
{
    
    type idxType = R.idxType;
    
    if R.size < indexPartitions.size then {
        halt("Range must contain at least as many elements as indexPartitions");
    }
    
    if boundsChecking then {
        for e in indexPartitions do {
            if e <= 0:real then {
                halt("Each element in indexPartitions must be greater than zero");
            }
        }
    }
    
    const indexDomain = indexPartitions.domain;
    const elements = R.size;
    const portionSum: real = + reduce indexPartitions;
    const fac: real = elements:real / portionSum;
    var exactPortions: [indexDomain] int;
    
    for idx in indexDomain do {
        const portion = indexPartitions(idx);
        const exactp = round(portion*fac):int;
        
        // Make sure no index will get zero elements
        exactPortions(idx) = if exactp > 1 then exactp else 1;
    }
    
    var currentElements = + reduce exactPortions;
    
    // If positive we need to add more elements; if negative we need to remove
    var elementDiff = elements - currentElements;
    
    // Is it sure that one iteration over elements is enough?
    // Assert to check this added.
    if elementDiff > 0 then {
        for e in exactPortions do {
            e += 1;
            elementDiff -= 1;
            if elementDiff == 0 then break;
        }
    } else if elementDiff < 0 then {
        for e in exactPortions do {
            if e >= 2 then {
                e -= 1;
                elementDiff += 1;
                if elementDiff == 0 then break;
            }
        }
    }
    assert( (+ reduce exactPortions) == elements );
    
    // Stores per-index partitions. Non-overlapping, cover from
    // min(idxType) to max(idxType)
    var ranges: [indexDomain] range(idxType);
    
    // Minimum and maximum indices to be cached
    const minCacheIdx = R.low + (exactPortions(indexDomain.dim(1).low) - 1);
    const maxCacheIdx = R.high - (exactPortions(indexDomain.dim(1).high) - 1);
    // const minCacheIdx = R.low ;
    // const maxCacheIdx = R.high ;
     
    // Cache array. From range's index to locale index
    const cache: [{minCacheIdx..maxCacheIdx}] int;
    
    // Fill tables defined above
    var currentStart = R.low;
    for idx in indexDomain do {
        const currentEnd = currentStart + exactPortions(idx) - 1;
        
        const tmpStart = if idx == indexDomain.low then min(idxType) else currentStart;
        const tmpEnd = if idx == indexDomain.high then max(idxType) else currentEnd;
        ranges(idx) = tmpStart..tmpEnd;
        
        const cacheIntersect = cache.domain(ranges(idx));
        cache[cacheIntersect] = idx;
        
        currentStart += exactPortions(idx);
    }
    
    writeln(" --- R: "+ranges:string);
    writeln(" --- C: "+cache:string);
    
    return (ranges, cache);
}


class SingleDirectionCutPolicy {
    
    // Following types are (or probably will be) needed by VariBlockDist and thus are always required
    param rank;
    type idxType;
    param tlocsRank = rank;
    type tlocsIdxType = int;
    type tlocsDomType = domain(tlocsRank, tlocsIdxType);
    type indexerType = SingleDirectionCutPolicyIndexer(rank, idxType);
    
    
    
    
    const dom: domain(rank, idxType);
    
    const targetLocsOriginalDomain: domain(1);
    const targetLocsOriginal: [targetLocsOriginalDomain] locale;
    
    var targetLocsDom: tlocsDomType;
    var cutdir: int;
    
    var cacheDom: domain(1);
    var cutCache: [cacheDom] int;
    
    proc SingleDirectionCutPolicy(dom: domain, cutdir:int = -1, targetLocales: [] locale = Locales, param rank = dom.rank, type idxType = dom.idxType) {
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
        
        if cutdir == -1 then {
            if rank == 1 then {
                cutdir = 1;
            } else {
                var maxid = 1;
                
                for i in 2..rank do {
                    if dom.dim(i).size > dom.dim(maxid).size then {
                        maxid = i;
                    }
                }
                this.cutdir = maxid;
            }
            
        } else if cutdir >= 1 && cutdir <= rank then {
            this.cutdir = cutdir;
        } else {
            halt("Invalid cutdir value");
        }
        
        
        
        this.dom = dom;
        
        this.targetLocsOriginalDomain = {0..#targetLocales.size};
        this.targetLocsOriginal = reshape(targetLocales, targetLocsOriginalDomain);
    }
    
    proc setupArrays() {
        
    }
    
    proc setupArrays(ref targetLocDom: tlocsDomType, targetLocArr: [targetLocDom] locale) {
        
        var ranges: rank*range;
        
        for param i in 1..rank do
                ranges(i) = 0..#1;
        
        ranges(cutdir) = 0..#targetLocsOriginal.size;
        targetLocDom = {(...ranges)};
        
        targetLocArr = reshape(targetLocsOriginal, targetLocDom);
        targetLocsDom = targetLocDom;
        
        
        
        
        cacheDom = {dom.dim(this.cutdir)};
        const r = cacheDom.size / targetLocsOriginalDomain.size + 1;
        const cm = cacheDom.low;
        for i in cacheDom do {
            cutCache(i) = (i-cm)/r;
        }
        
        const ip: [{1..#(targetLocsOriginalDomain.size)}] real = 1.0;
        
        computePartitioning(dom.dim(cutdir), ip);
        
        writeln("**************************************");
        writeln(cutCache);
        writeln("--------------------------------------");
    }
    
    proc computeChunk(locid) {
        
        const icut = if rank == 1 then locid else locid(cutdir);
        const lo = dom.dim(cutdir).low;
        const hi = dom.dim(cutdir).high;
        
       // const rlo = find_first(cutCache, icut);
       // const rhi = find_last(cutCache, icut);
        const rlo = FindFirst(cutCache, icut);
        const rhi = FindLast(cutCache, icut);
        assert(rlo(1) && rhi(1));
        
        const blo = if rlo(2) == lo then min(idxType) else rlo(2);
        const bhi = if rhi(2) == hi then max(idxType) else rhi(2);
        
        if rank == 1 {
            return {blo..bhi};
        } else {
            var inds: rank*range(idxType);
            for param i in 1..rank {
                if i == cutdir then {
                    inds(i) = blo..bhi;
                } else {
                    inds(i) = min(idxType)..max(idxType);
                }
            }
            return {(...inds)};
        }
    }
    
    proc makeIndexer() {
        return new SingleDirectionCutPolicyIndexer(dom, targetLocsDom, cutdir, cacheDom, cutCache);
    }
    
}

class SingleDirectionCutPolicyIndexer {
    param rank;
    type idxType;
    
    const dom: domain(rank);
    const targetLocDom: domain(rank);
    const cutdir: int;
    var cacheDom: domain(1);
    var cutCache: [cacheDom] int;
    
    proc SingleDirectionCutPolicyIndexer(dom: domain, targetLocDom: domain, cutdir:int, cacheDom, cutCache, param rank = dom.rank, type idxType = dom.idxType) {
        if dom.rank != rank then {
            compilerError("Rank and rank of domain don't match");
        }
        
        if idxType != dom.idxType then {
            compilerError("IdxTypes don't match");
        }
        
        this.cutdir = cutdir;
        this.dom = dom;
        this.targetLocDom = targetLocDom;
        
        this.cacheDom = cacheDom;
        this.cutCache = cutCache;
    }
    
    proc targetLocIdx(ind: rank*idxType) {
        var result: rank*int;
        for param i in 1..rank do {
            result(i) = 0;
        }
        
        const p = ind(cutdir);
        const cmin = cacheDom.low;
        const cmax = cacheDom.high;
        
        if p <= cmin then {
            result(cutdir) = cutCache(cmin);
        } else if p >= cmax then {
            result(cutdir) = cutCache(cmax);
        } else {
            result(cutdir) = cutCache(p);
        }
        
        /*
        const i = cutdir;
        result(i) = max(0, min((targetLocDom.dim(i).length-1):int,
                                (((ind(i) - dom.dim(i).low) *
                                    targetLocDom.dim(i).length:idxType) /
                                    dom.dim(i).length):int));*/
            
        return if rank == 1 then result(1) else result;
    }
}

class EvenPolicy {
    
    param rank;
    type idxType;
    
    type tlocsDomType = domain(rank, idxType);
    
    type indexerType = EvenPolicyIndexer(rank, idxType);
    
    const dom: domain(rank);
    
    const targetLocsOriginalDomain: domain(1);
    const targetLocsOriginal: [targetLocsOriginalDomain] locale;
    
    var targetLocsDom: tlocsDomType;
    
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
    
    proc setupArrays(ref targetLocDom: tlocsDomType, targetLocArr: [targetLocDom] locale) {
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