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



proc computePartitioning(R, indexPartitions)
    where indexPartitions.rank == 1 && indexPartitions.idxType == int
{
    
    type idxType = R.idxType;
    
    if R.size < indexPartitions.size then {
        halt("Range must contain at least as many elements as indexPartitions");
    }
    
    if boundsChecking then {
        writeln("--- "+indexPartitions:string);
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
    
    //writeln(" --- R: "+ranges:string);
    //writeln(" --- C: "+cache:string);
    
    return (ranges, cache);
}


proc computeCutDim(dom: domain, cutDim: int): int {
    param rank = dom.rank;
    if cutDim == -1 then {
        if rank == 1 then {
            cutDim = 1;
        } else {
            var maxDim = 1;
            
            for i in 2..rank do {
                if dom.dim(i).size > dom.dim(maxDim).size then {
                    maxDim = i;
                }
            }
            return maxDim;
        }
    } else if cutDim >= 1 && cutDim <= rank then {
        return cutDim;
    } else {
        halt("Invalid cutDim value");
    }
}


