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
use VariBlockPolicyHelpers;

record ArrayWrapper {
    param rank;
    type idxType;
    type eltType;
    var dom: domain(rank, idxType);
    var data: [dom] eltType;
}

class StaticCutPolicy {
    
    // Following types are (or probably will be) needed by VariBlockDist and thus are always required
    param rank;
    type idxType;
    param tlocsRank = rank;
    type tlocsIdxType = int;
    type tlocsDomType = domain(tlocsRank, tlocsIdxType);
    type indexerType = StaticCutPolicyIndexer(rank, idxType);
    
    // Following will be returned to the VariBlock by setup method
    var tlocsDom: domain(rank);
    var tlocsLocales: [tlocsDom] locale;
    var tlocsPortions: [tlocsDom] rank*range(idxType);
    
    // Data for indexer
    var cutCache: rank*ArrayWrapper(1, idxType, int);
    
    // Other studd
    var dom: domain(rank, idxType);
    
    /*
    proc StaticCutPolicy(dom: domain, targetLocs: [?targetLocsDom] locale, param rank = dom.rank, type idxType = dom.idxType, cuts: [] real ) {
        if k != rank then {
            compilerError("Wrong number of cut tables supplied");
        }
        
        var cutsWrapped: rank*ArrayWrapper(1, int, real);
        
        for i in 1..rank do {
            if cuts(i).domain.dim(1) != targetLocsDom.dim(i) then {
                halt("targetLocs and cuts don't match in dimension "+i);
            }
            cutsWrapped(i).dom = cuts(i).dom;
            cutsWrapped(i).data = cuts(i).data;
        }
        
        _initialize(dom, targetLocs, cutsWrapped);
    }*/
    
    proc StaticCutPolicy(dom: domain, targetLocs: [?targetLocsDom] locale, param rank = dom.rank, type idxType = dom.idxType)
    {
        _initialize(dom, targetLocs);
    }
    
    proc setCuts(dim: int, cuts: [?cutsDom] real)
        where cutsDom.rank == 1 && cutsDom.idxType == int
    {
        if cutsDom.dim(1) != tlocsDom.dim(dim) then {
            halt("Invalid size of cuts in dimensions "+dim);
        }
        
        const (_tlocsRanges, _tlocsCache) = computePartitioning(dom.dim(dim), cuts);
        
        // Set up tlocsPortions
        for i in tlocsDom do {
            tlocsPortions(i)(dim) = _tlocsRanges(i(dim));
        }
        
        // Set up cut cache
        cutCache(dim).dom = _tlocsCache.domain;
        cutCache(dim).data = _tlocsCache;
    }
    
    proc _initialize(dom: domain, targetLocs: [?targetLocsDom] locale)
        where dom.rank == rank && dom.idxType == idxType && targetLocs.idxType == int && targetLocs.rank == rank
    {
        if targetLocs.size < 1 then {
            halt("At least one locale needed to distribute...");
        }
        
        for i in 1..rank do {
            const ds = dom.dim(i).size;
            const ls = targetLocsDom.dim(i).size;
            
            if ds < ls then {
                halt("targetLocs array's size ("+ls+") is larger than the domain's ("+ds+") in dimension "+i);
            }
        }
        
        this.dom = dom;
        
        tlocsDom = targetLocsDom;
        tlocsLocales = targetLocs;
        
        for i in 1..rank do {
            const cuts: [tlocsDom.dim(i)] real = 1.0;
            setCuts(i, cuts);
        }
    }
    
    proc dump() {
        writeln();
        writeln("StaticCutPolicy dump:");
        writeln();
        writeln("Cut Cache");
        for i in 1..rank do {
            writeln("("+i:string+")["+cutCache(i).dom:string+"]: "+cutCache(i).data:string);
        }
        writeln();
        writeln("tlocsDom");
        writeln(tlocsDom);
        writeln();
        writeln("tlocsLocales");
        writeln(tlocsLocales);
        writeln();
        writeln("tlocsPortions");
        writeln(tlocsPortions);
        writeln();
    }
    
    
    proc setup( /* possible callbacks */ ) {
        return(tlocsDom, tlocsLocales, tlocsPortions);
    }
    
    proc makeIndexer() {
        return new StaticCutPolicyIndexer(cutCache, rank, idxType);
    }
    
    proc makeDomainTimer() {
        return nil;
    }
}

class StaticCutPolicyIndexer {
    param rank;
    type idxType;
    
    var cutCache: rank*ArrayWrapper(1, idxType, int);
    
    proc StaticCutPolicyIndexer(cutCache, param rank, type idxType) {
        this.cutCache = cutCache;
    }
    
    proc resInDim(dim: int, val: idxType) {
        const cmin = cutCache(dim).dom.low;
        const cmax = cutCache(dim).dom.high;
        
        if val <= cmin then {
            return cutCache(dim).data(cmin);
        } else if val >= cmax then {
            return cutCache(dim).data(cmax);
        }
        
        return cutCache(dim).data(val);
    }
    
    proc targetLocIdx(ind: rank*idxType) {
        var result: rank*int;
        for param i in 1..rank do {
            result(i) = resInDim(i, ind(i));
        }
        
        return if rank == 1 then result(1) else result;
    }
}

class SingleDirectionCutPolicy {
    
    // Following types are (or probably will be) needed by VariBlockDist and thus are always required
    param rank;
    type idxType;
    param tlocsRank = rank;
    type tlocsIdxType = int;
    type tlocsDomType = domain(tlocsRank, tlocsIdxType);
    type indexerType = SingleDirectionCutPolicyIndexer(rank, idxType);
    //type timerType = 
    
    // Currently must be zero-based to work. VariBlock should be modified so that this isn't the case
   // param 1 = 1;
    
    const dom: domain(rank, idxType);
    
    const targetLocsOriginalDomain: domain(1);
    const targetLocsOriginal: [targetLocsOriginalDomain] locale;
    
    var targetLocsDom: tlocsDomType;
    const cutDim: int;
    
    // Cache data for indexers
    var cutCacheDom: domain(1, idxType);
    var cutCache: [cutCacheDom] int;
    
    // Following will be returned to the VariBlock by setup method
    var tlocsDom: domain(rank);
    var tlocsLocales: [tlocsDom] locale;
    var tlocsPortions: [tlocsDom] rank*range(idxType);
    
    proc SingleDirectionCutPolicy(dom: domain, cutDim:int = -1, param rank = dom.rank, type idxType = dom.idxType) {
        var targetLocales: [LocaleSpace] (locale, real);
        forall i in LocaleSpace do {
            targetLocales(i) = (Locales(i), 1.0);
        }
        
        _initilize(dom, targetLocales, cutDim);
    }
    
    proc SingleDirectionCutPolicy(dom: domain, targetLocales: [] (locale, real), cutDim:int = -1, param rank = dom.rank, type idxType = dom.idxType) {
        _initilize(dom, targetLocales, cutDim);
    }
    
    proc _initilize(dom: domain(rank, idxType), targetLocales: [?targetLocalesDom] (locale, real), cutDim:int)
        where targetLocalesDom.rank == 1
    {
        
        // Make sure some values are correct
        if targetLocales.size < 1 then {
            halt("At least one locale needed to distribute...");
        }
        
        if targetLocales.size > dom.size then {
            halt("Domain to be distributed needs to have at least as many indices as there are locales across which to distribute.");
        }
        
        // Make sure cutDim is valid, and possibly calculate the dimension
        this.cutDim = computeCutDim(dom, cutDim);
        
        // Set up tlocsDom
        {
            var ranges: rank*range;
            for param i in 1..rank do {
                ranges(i) = 1..#1;
            }
            ranges(1) = 1..#targetLocales.size;
            tlocsDom = {(...ranges)};
        }
        
        // Set up tlocsLocales and tlocsRelativePortions
        var tlocsRelativePortions: [1..#targetLocales.size] real;
        
        {
            var targetLocalesReindex: [1..#targetLocales.size] => targetLocales;
            forall i in tlocsDom do {
                tlocsLocales(i) = targetLocalesReindex(i(1))(1);
                tlocsRelativePortions(i(1)) = targetLocalesReindex(i(1))(2);
            }
        }
        
        // Calculate how the domain is split
        const (_tlocsRanges, _tlocsCache) = computePartitioning(dom.dim(this.cutDim), tlocsRelativePortions);
        
        // Set up tlocsPortions
        {
            const rangeMinMax = min(idxType)..max(idxType);
            for i in tlocsDom do {
                var ranges: rank*range(idxType);
                for param i in 1..rank do {
                    ranges(i) = rangeMinMax;
                }
                ranges(this.cutDim) = _tlocsRanges(i(1));
                tlocsPortions(i) = ranges;
                //tlocsPortions(i) = {(...ranges)};
            }
        }
        
        // Set up cut cache
        cutCacheDom = _tlocsCache.domain;
        cutCache = _tlocsCache;
    }
    
    proc setup( /* possible callbacks */ ) {
        return(tlocsDom, tlocsLocales, tlocsPortions);
    }
    
    proc makeIndexer() {
        return new SingleDirectionCutPolicyIndexer(this.cutDim, cutCache, rank, idxType);
    }
    
    proc makeDomainTimer() {
        return nil;
    }
    
    proc dump() {
        writeln();
        writeln("SingleDirectionCutPolicy dump:");
        writeln();
        writeln("Cut Cache");
        writeln(cutCacheDom);
        writeln(cutCache);
        writeln();
        writeln("tlocsDom");
        writeln(tlocsDom);
        writeln();
        writeln("tlocsLocales");
        writeln(tlocsLocales);
        writeln();
        writeln("tlocsPortions");
        writeln(tlocsPortions);
        writeln();
    }
}

class SingleDirectionCutPolicyIndexer {
    param rank;
    type idxType;
    
    var cutDim: int;
    var cutCacheDom: domain(1, idxType);
    var cutCache: [cutCacheDom] int;
    
    proc SingleDirectionCutPolicyIndexer(cutDim:int, cutCache, param rank, type idxType) {
        this.cutDim = cutDim;
        this.cutCacheDom = cutCache.domain;
        this.cutCache = cutCache;
    }
    
    proc targetLocIdx(ind: rank*idxType) {
        var result: rank*int;
        for param i in 1..rank do {
            result(i) = 1;
        }
        
        const p = ind(cutDim);
        const cmin = cutCacheDom.low;
        const cmax = cutCacheDom.high;
        
        if p <= cmin then {
            result(cutDim) = cutCache(cmin);
        } else if p >= cmax then {
            result(cutDim) = cutCache(cmax);
        } else {
            result(cutDim) = cutCache(p);
        }
        
        return if rank == 1 then result(1) else result;
    }
}



class EvenPolicy {
    
    param rank;
    type idxType;
    param tlocsRank = rank;
    type tlocsIdxType = int;
    type tlocsDomType = domain(tlocsRank, tlocsIdxType);
    type indexerType = EvenPolicyIndexer(rank, idxType);
    
    
    
    const dom: domain(rank, idxType);
    
    
    // Following will be returned to the VariBlock by setup method
    var tlocsDom: domain(rank);
    var tlocsLocales: [tlocsDom] locale;
    var tlocsPortions: [tlocsDom] rank*range(idxType);
    
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
        
       // this.targetLocsOriginalDomain = {0..#targetLocales.size};
       // this.targetLocsOriginal = reshape(targetLocales, targetLocsOriginalDomain);
        
        
        if rank != 1 && targetLocales.rank == 1 {
            const factors = _factor(rank, targetLocales.numElements);
            var ranges: rank*range;
            for param i in 1..rank do {
                ranges(i) = 0..#factors(i);
            }
            
            tlocsDom = {(...ranges)};
            tlocsLocales = reshape(targetLocales, tlocsDom);
        } else {
            if targetLocales.rank != rank then {
                compilerError("specified target array of locales must equal 1 or distribution rank");
            }
            
            var ranges: rank*range;
            for param i in 1..rank do {
                ranges(i) = 0..#targetLocales.domain.dim(i).length;
            }
            
            tlocsDom = {(...ranges)};
            tlocsLocales = targetLocales;
        }
        
        
        
        
        
        
        
        proc _computeChunk(locid): rank*range(idxType) {
            const boundingBox = dom.dims();
            const targetLocBox = tlocsDom.dims();
            if rank == 1 {
                var inds: rank*range(idxType);
                const lo = boundingBox(1).low;
                const hi = boundingBox(1).high;
                const numelems = hi - lo + 1;
                const numlocs = targetLocBox(1).length;
                const(chi, clo) = _computeBlock(numelems, numlocs, locid, max(idxType), min(idxType), lo);
                inds(1) = chi..clo;
                return inds;
            } else {
                var inds: rank*range(idxType);
                for param i in 1..rank {
                    const lo = boundingBox(i).low;
                    const hi = boundingBox(i).high;
                    const numelems = hi - lo + 1;
                    const numlocs = targetLocBox(i).length;
                    const (blo, bhi) = _computeBlock(numelems, numlocs, locid(i), max(idxType), min(idxType), lo);
                    inds(i) = blo..bhi;
                }
                return inds;
            }
        }
        
        
        forall i in tlocsDom do {
            tlocsPortions(i) = _computeChunk(i);
        } 
    }
    

    
    proc setup( /* possible callbacks */ ) {
        return(tlocsDom, tlocsLocales, tlocsPortions);
    }
    
    proc makeIndexer() {
        return new EvenPolicyIndexer(dom, tlocsDom);
        //return nil;
    }
    
    proc makeDomainTimer() {
        return nil;
    }
    
    proc dump() {
        writeln();
        writeln("EvenPolicy dump:");
        writeln();
        writeln("tlocsDom");
        writeln(tlocsDom);
        writeln();
        writeln("tlocsLocales");
        writeln(tlocsLocales);
        writeln();
        writeln("tlocsPortions");
        writeln(tlocsPortions);
        writeln();
    }
}

class EvenPolicyIndexer {
    param rank;
    type idxType;
    
    const dom: domain(rank, idxType);
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
