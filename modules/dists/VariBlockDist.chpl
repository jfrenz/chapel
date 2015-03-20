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

//
// The VariBlock distribution is defined with six classes:
//
//   VariBlock       : distribution class
//   VariBlockDom    : domain class
//   VariBlockArr    : array class
//   LocVariBlock    : local distribution class (per-locale instances)
//   LocVariBlockDom : local domain class (per-locale instances)
//   LocVariBlockArr : local array class (per-locale instances)
//
// When a distribution, domain, or array class instance is created, a
// correponding local class instance is created on each locale that is
// mapped to by the distribution.
//

// TO DO List
//
// 1. refactor pid fields from distribution, domain, and array classes
//

use DSIUtil;
use ChapelUtil;
use CommDiagnostics;

use VariBlockTimers;
use Time;


//
// These flags are used to output debug information and run extra
// checks when using VariBlock.  Should these be promoted so that they can
// be used across all distributions?  This can be done by turning them
// into compiler flags or adding config parameters to the internal
// modules, perhaps called debugDists and checkDists.
//
config param debugVariBlockDist = false;
config param debugVariBlockDistBulkTransfer = false;

// This flag is used to enable bulk transfer when aliased arrays are
// involved.  Currently, aliased arrays are not eligible for the
// optimization due to a bug in bulk transfer for rank changed arrays
// in which the last (right-most) dimension is collapsed.  Disabling
// the optimization for all aliased arrays is very conservative, so
// we provide this flag to allow the user to override the decision,
// with the caveat that it will likely not work for the above case.
config const disableAliasedBulkTransfer = true;

config param sanityCheckDistribution = false;

//
// If the testFastFollowerOptimization flag is set to true, the
// follower will write output to indicate whether the fast follower is
// used or not.  This is used in regression testing to ensure that the
// 'fast follower' optimization is working.
//
config param testFastFollowerOptimization = false;

//
// This flag is used to disable lazy initialization of the RAD cache.
//
//config param disableVariBlockLazyRAD = defaultDisableLazyRADOpt;
config param disableVariBlockLazyRAD = true;

// Disabling timing support when not needed improves performance a bit.
config param enableVariBlockTimings = true;


//
// VariBlock Distribution Class
//
//   The fields dataParTasksPerLocale, dataParIgnoreRunningTasks, and
//   dataParMinGranularity can be changed, but changes are
//   not reflected in privatized copies of this distribution.  Perhaps
//   this is a feature, not a bug?!
//
// rank : generic rank that must match the rank of domains and arrays
//        declared over this distribution
//
// idxType: generic index type that must match the index type of
//          domains and arrays declared over this distribution
//
// boundingBox: a non-distributed domain defining a bounding box used
//              to partition the space of all indices across the array
//              of target locales; the indices inside the bounding box
//              are partitioned "evenly" across the locales and
//              indices outside the bounding box are mapped to the
//              same locale as the nearest index inside the bounding
//              box
//
// targetLocDom: a non-distributed domain over which the array of
//               target locales and the array of local distribution
//               classes are defined
//
// targetLocales: a non-distributed array containing the target
//                locales to which this distribution partitions indices
//                and data
//
// locDist: a non-distributed array of local distribution classes
//
// dataParTasksPerLocale: an integer that specifies the number of tasks to
//                        use on each locale when iterating in parallel over
//                        a VariBlock-distributed domain or array
//
// dataParIgnoreRunningTasks: a boolean what dictates whether the number of
//                            task use on each locale should be limited
//                            by the available parallelism
//
// dataParMinGranularity: the minimum required number of elements per
//                        task created
//
class VariBlock : BaseDist {
  var timer: VariBlockTimers.VB_TimerBase_Dmap;
  var policy;
  var indexer: policy.indexerType;
  
  param rank: int;
  type idxType = int;
  var boundingBox: domain(rank, idxType);
  //var targetLocDom: policy.tlocsDomType;
  var targetLocDom: domain(rank);
  var targetLocales: [targetLocDom] locale;
  var locDist: [targetLocDom] LocVariBlock(rank, idxType);
  var dataParTasksPerLocale: int;
  var dataParIgnoreRunningTasks: bool;
  var dataParMinGranularity: int;
  var pid: int = -1; // privatized object id (this should be factored out)
}

//
// Local VariBlock Distribution Class
//
// rank : generic rank that matches VariBlock.rank
// idxType: generic index type that matches VariBlock.idxType
// myChunk: a non-distributed domain that defines this locale's indices
//
class LocVariBlock {
  param rank: int;
  type idxType;
  const myChunk: domain(rank, idxType);
}

//
// VariBlock Domain Class
//
// rank:      generic domain rank
// idxType:   generic domain index type
// stridable: generic domain stridable parameter
// dist:      reference to distribution class
// locDoms:   a non-distributed array of local domain classes
// whole:     a non-distributed domain that defines the domain's indices
//
class VariBlockDom: BaseRectangularDom {
  type policyType;
  
  param rank: int;
  type idxType;
  param stridable: bool;
  const dist: VariBlock(policyType, rank, idxType);
  var locDoms: [dist.targetLocDom] LocVariBlockDom(rank, idxType, stridable);
  var whole: domain(rank=rank, idxType=idxType, stridable=stridable);
  var pid: int = -1; // privatized object id (this should be factored out)
  
  var timer: VariBlockTimers.VB_TimerBase_Domain;
}

//
// Local VariBlock Domain Class
//
// rank: generic domain rank
// idxType: generic domain index type
// stridable: generic domain stridable parameter
// myVariBlock: a non-distributed domain that defines the local indices
//
class LocVariBlockDom {
  param rank: int;
  type idxType;
  param stridable: bool;
  var myVariBlock: domain(rank, idxType, stridable);
}

//
// VariBlock Array Class
//
// eltType: generic array element type
// rank: generic array rank
// idxType: generic array index type
// stridable: generic array stridable parameter
// dom: reference to domain class
// locArr: a non-distributed array of local array classes
// myLocArr: optimized reference to here's local array class (or nil)
//
class VariBlockArr: BaseArr {
  type policyType;
  
  type eltType;
  param rank: int;
  type idxType;
  param stridable: bool;
  var doRADOpt: bool = defaultDoRADOpt;
  var dom: VariBlockDom(policyType, rank, idxType, stridable);
  var locArr: [dom.dist.targetLocDom] LocVariBlockArr(eltType, rank, idxType, stridable);
  var myLocArr: LocVariBlockArr(eltType, rank, idxType, stridable);
  var pid: int = -1; // privatized object id (this should be factored out)
  const SENTINEL = max(rank*idxType);
}

//
// Local VariBlock Array Class
//
// eltType: generic array element type
// rank: generic array rank
// idxType: generic array index type
// stridable: generic array stridable parameter
// locDom: reference to local domain class
// myElems: a non-distributed array of local elements
//
class LocVariBlockArr {
  type eltType;
  param rank: int;
  type idxType;
  param stridable: bool;
  const locDom: LocVariBlockDom(rank, idxType, stridable);
  var locRAD: LocRADCache(eltType, rank, idxType); // non-nil if doRADOpt=true
  var myElems: [locDom.myVariBlock] eltType;
  var locRADLock: atomicflag; // This will only be accessed locally
                              // force the use of processor atomics
  
  
  // These function will always be called on this.locale, and so we do
  // not have an on statement around the while loop below (to avoid
  // the repeated on's from calling testAndSet()).
  inline proc lockLocRAD() {
    while locRADLock.testAndSet() do chpl_task_yield();
  }

  inline proc unlockLocRAD() {
    locRADLock.clear();
  }
}

//
// VariBlock constructor for clients of the VariBlock distribution
//
proc VariBlock.VariBlock(boundingBox: domain,
                
                policy,
                
                dataParTasksPerLocale=getDataParTasksPerLocale(),
                dataParIgnoreRunningTasks=getDataParIgnoreRunningTasks(),
                dataParMinGranularity=getDataParMinGranularity(),
                param rank = boundingBox.rank,
                type idxType = boundingBox.idxType) {
  if rank != boundingBox.rank then
    compilerError("specified VariBlock rank != rank of specified bounding box");
  if idxType != boundingBox.idxType then
    compilerError("specified VariBlock index type != index type of specified bounding box");
  
  if !isClass(policy) then {
    compilerError("Policy must be of class type");
  }
  
  if policy == nil then {
    halt("Policy must not be nil");
  }
  
  /*this.timer = if enableVariBlockTimings && timer != nil then
                 timer.getNewDmapTimer()
               else
                 nil;*/
  
  const setupData = policy.setup();
  this.targetLocDom = setupData(1);
  this.targetLocales = setupData(2);
  const chunks = setupData(3);
  
  
  this.boundingBox = boundingBox;
  this.timer = nil;
  //policy.setupArrays(this.targetLocDom, this.targetLocales);
  
  

  indexer = policy.makeIndexer();
  
  const boundingBoxDims = boundingBox.dims();
  const targetLocDomDims = targetLocDom.dims();
  coforall locid in targetLocDom do
    on this.targetLocales(locid) do
      locDist(locid) =  new LocVariBlock({(...chunks(locid))});

  // NOTE: When these knobs stop using the global defaults, we will need
  // to add checks to make sure dataParTasksPerLocale<0 and
  // dataParMinGranularity<0
  this.dataParTasksPerLocale = if dataParTasksPerLocale==0
                               then here.maxTaskPar
                               else dataParTasksPerLocale;
  this.dataParIgnoreRunningTasks = dataParIgnoreRunningTasks;
  this.dataParMinGranularity = dataParMinGranularity;

  if debugVariBlockDist {
    writeln("Creating new VariBlock distribution:");
    dsiDisplayRepresentation();
  }
}

proc VariBlock.dsiAssign(other: this.type) {
  coforall locid in targetLocDom do
    on targetLocales(locid) do
      delete locDist(locid);
  boundingBox = other.boundingBox;
  targetLocDom = other.targetLocDom;
  targetLocales = other.targetLocales;
  
  dataParTasksPerLocale = other.dataParTasksPerLocale;
  dataParIgnoreRunningTasks = other.dataParIgnoreRunningTasks;
  dataParMinGranularity = other.dataParMinGranularity;
  
  
  policy = other.policy;
  indexer = policy.makeIndexer();
  
  timer = if enableVariBlockTimings && other.timer != nil then
            other.timer.getNewDmapTimer()
          else
            nil;
  
  const boundingBoxDims = boundingBox.dims();
  const targetLocDomDims = targetLocDom.dims();

  coforall locid in targetLocDom do
    on targetLocales(locid) do
      locDist(locid) = new LocVariBlock(policy.computeChunk(locid));
}

proc VariBlock.dsiClone() {
  return new VariBlock(boundingBox, policy,
                   dataParTasksPerLocale, dataParIgnoreRunningTasks,
                   dataParMinGranularity);
}

proc VariBlock.dsiDestroyDistClass() {
  coforall ld in locDist do {
    on ld do
      delete ld;
  }
}

proc VariBlock.dsiDisplayRepresentation() {
  writeln("boundingBox = ", boundingBox);
  writeln("targetLocDom = ", targetLocDom);
  writeln("targetLocales = ", for tl in targetLocales do tl.id);
  writeln("dataParTasksPerLocale = ", dataParTasksPerLocale);
  writeln("dataParIgnoreRunningTasks = ", dataParIgnoreRunningTasks);
  writeln("dataParMinGranularity = ", dataParMinGranularity);
  for tli in targetLocDom do
    writeln("locDist[", tli, "].myChunk = ", locDist[tli].myChunk);
}

proc VariBlock.makeDomainTimer() {
    const _tim = if enableVariBlockTimings then
                 policy.makeDomainTimer()
             else
                 nil:VariBlockTimers.VB_TimerBase_Domain;
    return _tim;
}

proc VariBlock.dsiNewRectangularDom(param rank: int, type idxType,
                              param stridable: bool) {
  if idxType != this.idxType then
    compilerError("VariBlock domain index type does not match distribution's");
  if rank != this.rank then
    compilerError("VariBlock domain rank does not match distribution's");

  var dom = new VariBlockDom(policyType=policy.type, rank=rank, idxType=idxType, dist=this, stridable=stridable, timer=this.makeDomainTimer());
  dom.setup();
  if debugVariBlockDist {
    writeln("Creating new VariBlock domain:");
    dom.dsiDisplayRepresentation();
  }
  return dom;
}

//
// output distribution
//
proc VariBlock.writeThis(x:Writer) {
  x.writeln("VariBlock");
  x.writeln("-------");
  x.writeln("distributes: ", boundingBox);
  x.writeln("across locales: ", targetLocales);
  x.writeln("indexed via: ", targetLocDom);
  x.writeln("resulting in: ");
  for locid in targetLocDom do
    x.writeln("  [", locid, "] locale ", locDist(locid).locale.id, " owns chunk: ", locDist(locid).myChunk);
}

proc VariBlock.dsiIndexToLocale(ind: idxType) where rank == 1 {
  return targetLocales(targetLocsIdx(ind));
}

proc VariBlock.dsiIndexToLocale(ind: rank*idxType) where rank > 1 {
  return targetLocales(targetLocsIdx(ind));
}

//
// compute what chunk of inds is owned by a given locale -- assumes
// it's being called on the locale in question
//
proc VariBlock.getChunk(inds, locid) {
  // use domain slicing to get the intersection between what the
  // locale owns and the domain's index set
  //
  // TODO: Should this be able to be written as myChunk[inds] ???
  //
  // TODO: Does using David's detupling trick work here?
  //
  const chunk = locDist(locid).myChunk((...inds.getIndices()));
  if sanityCheckDistribution then
    if chunk.numIndices > 0 {
      if targetLocsIdx(chunk.low) != locid then
        writeln("[", here.id, "] ", chunk.low, " is in my chunk but maps to ",
                targetLocsIdx(chunk.low));
      if targetLocsIdx(chunk.high) != locid then
        writeln("[", here.id, "] ", chunk.high, " is in my chunk but maps to ",
                targetLocsIdx(chunk.high));
    }
  return chunk;
}

//
// get the index into the targetLocales array for a given distributed index
//


proc VariBlock.targetLocsIdx(ind: idxType) where rank == 1 {
  return targetLocsIdx((ind,));
}

proc VariBlock.targetLocsIdx(ind: rank*idxType){
  return indexer.targetLocIdx(ind);
}


/*
proc VariBlock.targetLocsIdx(ind: rank*idxType) {
  var result: rank*int;
  for param i in 1..rank do
    result(i) = max(0, min((targetLocDom.dim(i).length-1):int,
                           (((ind(i) - boundingBox.dim(i).low) *
                             targetLocDom.dim(i).length:idxType) /
                            boundingBox.dim(i).length):int));
  return if rank == 1 then result(1) else result;
}
*/


proc LocVariBlock.LocVariBlock(myChunk: domain, param rank = myChunk.rank, type idxType = myChunk.idxType) {
    this.myChunk = myChunk;
}
    
proc VariBlockDom.dsiMyDist() return dist;

proc VariBlockDom.dsiDisplayRepresentation() {
  writeln("whole = ", whole);
  for tli in dist.targetLocDom do
    writeln("locDoms[", tli, "].myVariBlock = ", locDoms[tli].myVariBlock);
}

proc VariBlockDom.dsiDims() return whole.dims();

proc VariBlockDom.dsiDim(d: int) return whole.dim(d);

// stopgap to avoid accessing locDoms field (and returning an array)
proc VariBlockDom.getLocDom(localeIdx) return locDoms(localeIdx);


//
// Given a tuple of scalars of type t or range(t) match the shape but
// using types rangeType and scalarType e.g. the call:
// _matchArgsShape(range(int(32)), int(32), (1:int(64), 1:int(64)..5, 1:int(64)..5))
// returns the type: (int(32), range(int(32)), range(int(32)))
//
proc _matchArgsShape(type rangeType, type scalarType, args) type {
  proc helper(param i: int) type {
    if i == args.size {
      if isCollapsedDimension(args(i)) then
        return (scalarType,);
      else
        return (rangeType,);
    } else {
      if isCollapsedDimension(args(i)) then
        return (scalarType, (... helper(i+1)));
      else
        return (rangeType, (... helper(i+1)));
    }
  }
  return helper(1);
}


iter VariBlockDom.these() {
  for i in whole do
    yield i;
}

iter VariBlockDom.these(param tag: iterKind) where tag == iterKind.leader {
  if enableVariBlockTimings && timer != nil && timer.timeNext() then {
    for followThis in these(tag, true) do {
      yield followThis;
    }
  } else {
    for followThis in these(tag, false) do {
      yield followThis;
    }   
  }
}

iter VariBlockDom.these(param tag: iterKind, param timed)
    where tag == iterKind.leader && timed == false
{
  const maxTasks = dist.dataParTasksPerLocale;
  const ignoreRunning = dist.dataParIgnoreRunningTasks;
  const minSize = dist.dataParMinGranularity;
  const wholeLow = whole.low;

  // If this is the only task running on this locale, we don't want to
  // count it when we try to determine how many tasks to use.  Here we
  // check if we are the only one running, and if so, use
  // ignoreRunning=true for this locale only.  Obviously there's a bit
  // of a race condition if some other task starts after we check, but
  // in that case there is no correct answer anyways.
  //
  // Note that this code assumes that any locale will only be in the
  // targetLocales array once.  If this is not the case, then the
  // tasks on this locale will *all* ignoreRunning, which may have
  // performance implications.
  const hereId = here.id;
  const hereIgnoreRunning = if here.runningTasks() == 1 then true
                            else ignoreRunning;
  coforall locDom in locDoms do on locDom {
    const myIgnoreRunning = if here.id == hereId then hereIgnoreRunning
      else ignoreRunning;
    // Use the internal function for untranslate to avoid having to do
    // extra work to negate the offset
    type strType = chpl__signedType(idxType);
    const tmpVariBlock = locDom.myVariBlock.chpl__unTranslate(wholeLow);
    var locOffset: rank*idxType;
    for param i in 1..tmpVariBlock.rank do
      locOffset(i) = tmpVariBlock.dim(i).first/tmpVariBlock.dim(i).stride:strType;
    // Forward to defaultRectangular
    for followThis in tmpVariBlock._value.these(iterKind.leader, maxTasks,
                                            myIgnoreRunning, minSize,
                                            locOffset) do
      yield followThis;
  }
}

iter VariBlockDom.these(param tag: iterKind, param timed)
    where tag == iterKind.leader && timed == true
{

  const maxTasks = dist.dataParTasksPerLocale;
  const ignoreRunning = dist.dataParIgnoreRunningTasks;
  const minSize = dist.dataParMinGranularity;
  const wholeLow = whole.low;
  
  const hereId = here.id;
  const hereIgnoreRunning = if here.runningTasks() == 1 then true
                            else ignoreRunning;
  
  var timres: [LocaleSpace] real;
  
  coforall locDom in locDoms do on locDom {
    const _t: Timer;
    _t.start();
    
    const myIgnoreRunning = if here.id == hereId then hereIgnoreRunning
      else ignoreRunning;
    // Use the internal function for untranslate to avoid having to do
    // extra work to negate the offset
    type strType = chpl__signedType(idxType);
    const tmpVariBlock = locDom.myVariBlock.chpl__unTranslate(wholeLow);
    var locOffset: rank*idxType;
    for param i in 1..tmpVariBlock.rank do
      locOffset(i) = tmpVariBlock.dim(i).first/tmpVariBlock.dim(i).stride:strType;
    // Forward to defaultRectangular
    for followThis in tmpVariBlock._value.these(iterKind.leader, maxTasks,
                                            myIgnoreRunning, minSize,
                                            locOffset) do
      yield followThis;
    
    _t.stop();
    //timer.processTiming(here.id, _t.elapsed());
    timres[here.id] = _t.elapsed();
  }
  timer.processTimings(timres);
}


//
// TODO: Abstract the addition of low into a function?
// Note relationship between this operation and the
// order/position functions -- any chance for creating similar
// support? (esp. given how frequent this seems likely to be?)
//
// TODO: Is there some clever way to invoke the leader/follower
// iterator on the local blocks in here such that the per-core
// parallelism is expressed at that level?  Seems like a nice
// natural composition and might help with my fears about how
// stencil communication will be done on a per-locale basis.
//
iter VariBlockDom.these(param tag: iterKind, followThis) where tag == iterKind.follower {
  proc anyStridable(rangeTuple, param i: int = 1) param
      return if i == rangeTuple.size then rangeTuple(i).stridable
             else rangeTuple(i).stridable || anyStridable(rangeTuple, i+1);

  if chpl__testParFlag then
    chpl__testPar("VariBlock domain follower invoked on ", followThis);

  var t: rank*range(idxType, stridable=stridable||anyStridable(followThis));
  type strType = chpl__signedType(idxType);
  for param i in 1..rank {
    var stride = whole.dim(i).stride: strType;
    // not checking here whether the new low and high fit into idxType
    var low = (stride * followThis(i).low:strType):idxType;
    var high = (stride * followThis(i).high:strType):idxType;
    t(i) = (low..high by stride:strType) + whole.dim(i).low by followThis(i).stride:strType;
  }
  for i in {(...t)} {
    yield i;
  }
}

//
// output domain
//
proc VariBlockDom.dsiSerialWrite(x:Writer) {
  x.write(whole);
}


//
// how to allocate a new array over this domain
//
proc VariBlockDom.dsiBuildArray(type eltType) {      
    
  var arr = new VariBlockArr(policyType=policyType, eltType=eltType, rank=rank, idxType=idxType, stridable=stridable, dom=this);
  arr.setup();
  return arr;
}

proc VariBlockDom.dsiNumIndices return whole.numIndices;
proc VariBlockDom.dsiLow return whole.low;
proc VariBlockDom.dsiHigh return whole.high;
proc VariBlockDom.dsiStride return whole.stride;

//
// INTERFACE NOTES: Could we make dsiSetIndices() for a rectangular
// domain take a domain rather than something else?
//
proc VariBlockDom.dsiSetIndices(x: domain) {
  if x.rank != rank then
    compilerError("rank mismatch in domain assignment");
  if x._value.idxType != idxType then
    compilerError("index type mismatch in domain assignment");
  whole = x;
  setup();
  if debugVariBlockDist {
    writeln("Setting indices of VariBlock domain:");
    dsiDisplayRepresentation();
  }
}

proc VariBlockDom.dsiSetIndices(x) {
  if x.size != rank then
    compilerError("rank mismatch in domain assignment");
  if x(1).idxType != idxType then
    compilerError("index type mismatch in domain assignment");
  //
  // TODO: This seems weird:
  //
  whole.setIndices(x);
  setup();
  if debugVariBlockDist {
    writeln("Setting indices of VariBlock domain:");
    dsiDisplayRepresentation();
  }
}

proc VariBlockDom.dsiGetIndices() {
  return whole.getIndices();
}

// dsiLocalSlice
proc VariBlockDom.dsiLocalSlice(param stridable: bool, ranges) {
  return whole((...ranges));
}

proc VariBlockDom.setup() {
  if locDoms(dist.targetLocDom.low) == nil {
    coforall localeIdx in dist.targetLocDom do {
      on dist.targetLocales(localeIdx) do
        locDoms(localeIdx) = new LocVariBlockDom(rank, idxType, stridable,
                                             dist.getChunk(whole, localeIdx));
    }
  } else {
    coforall localeIdx in dist.targetLocDom do {
      on dist.targetLocales(localeIdx) do
        locDoms(localeIdx).myVariBlock = dist.getChunk(whole, localeIdx);
    }
  }
}

proc VariBlockDom.dsiMember(i) {
  return whole.member(i);
}

proc VariBlockDom.dsiIndexOrder(i) {
  return whole.indexOrder(i);
}

//
// build a new rectangular domain using the given range
//
proc VariBlockDom.dsiBuildRectangularDom(param rank: int, type idxType,
                                   param stridable: bool,
                                   ranges: rank*range(idxType,
                                                      BoundedRangeType.bounded,
                                                      stridable)) {
  if idxType != dist.idxType then
    compilerError("VariBlock domain index type does not match distribution's");
  if rank != dist.rank then
    compilerError("VariBlock domain rank does not match distribution's");

  var dom = new VariBlockDom(policyType=policyType, rank=rank, idxType=idxType,
                         dist=dist, stridable=stridable, timer=dist.makeDomainTimer());
  dom.dsiSetIndices(ranges);
  return dom;
}

//
// Added as a performance stopgap to avoid returning a domain
//
proc LocVariBlockDom.member(i) return myVariBlock.member(i);

proc VariBlockArr.dsiDisplayRepresentation() {
  for tli in dom.dist.targetLocDom {
    writeln("locArr[", tli, "].myElems = ", for e in locArr[tli].myElems do e);
    if doRADOpt then
      writeln("locArr[", tli, "].locRAD = ", locArr[tli].locRAD.RAD);
  }
}

proc VariBlockArr.dsiGetBaseDom() return dom;

//
// NOTE: Each locale's myElems array be initialized prior to setting up
// the RAD cache.
//
proc VariBlockArr.setupRADOpt() {
  for localeIdx in dom.dist.targetLocDom {
    on dom.dist.targetLocales(localeIdx) {
      const myLocArr = locArr(localeIdx);
      if myLocArr.locRAD != nil {
        delete myLocArr.locRAD;
        myLocArr.locRAD = nil;
      }
      if disableVariBlockLazyRAD {
        myLocArr.locRAD = new LocRADCache(eltType, rank, idxType, dom.dist.targetLocDom);
        for l in dom.dist.targetLocDom {
          if l != localeIdx {
            myLocArr.locRAD.RAD(l) = locArr(l).myElems._value.dsiGetRAD();
          }
        }
      }
    }
  }
}

proc VariBlockArr.setup() {
  
  var thisid = this.locale.id;
  coforall localeIdx in dom.dist.targetLocDom {
    on dom.dist.targetLocales(localeIdx) {
      const locDom = dom.getLocDom(localeIdx);
      locArr(localeIdx) = new LocVariBlockArr(eltType, rank, idxType, stridable, locDom);
      if thisid == here.id then
        myLocArr = locArr(localeIdx);
    }
  }

  if doRADOpt && disableVariBlockLazyRAD then setupRADOpt();
}

inline proc _remoteAccessData.getDataIndex_VB(param stridable, ind: rank*idxType) {
  // modified from DefaultRectangularArr.getDataIndex
  if stridable {
    var sum = origin;
    for param i in 1..rank do
      sum += (ind(i) - off(i)) * blk(i) / abs(str(i)):idxType;
    return sum;
  } else {
    var sum = if earlyShiftData then 0:idxType else origin;
    for param i in 1..rank do
      sum += ind(i) * blk(i);
    if !earlyShiftData then sum -= factoredOffs;
    return sum;
  }
}


inline proc VariBlockArr.dsiLocalAccess(i: rank*idxType) ref {
  return myLocArr.this(i);
}

//
// the global accessor for the array
//
// TODO: Do we need a global bounds check here or in targetLocsIdx?
//
proc VariBlockArr.dsiAccess(i: rank*idxType) ref {
  local {
    if myLocArr != nil && myLocArr.locDom.member(i) then
      return myLocArr.this(i);
  }
  if doRADOpt {
    if myLocArr {
      if boundsChecking then
        if !dom.dsiMember(i) then
          halt("array index out of bounds: ", i);
      var rlocIdx = dom.dist.targetLocsIdx(i);
      if !disableVariBlockLazyRAD {
        if myLocArr.locRAD == nil {
          myLocArr.lockLocRAD();
          if myLocArr.locRAD == nil {
            var tempLocRAD = new LocRADCache(eltType, rank, idxType, dom.dist.targetLocDom);
            tempLocRAD.RAD.blk = SENTINEL;
            myLocArr.locRAD = tempLocRAD;
          }
          myLocArr.unlockLocRAD();
        }
        // NOTE: This is a known, benign race.  Multiple tasks may be
        // initializing the RAD cache entries at once, but our belief is
        // that this is infrequent enough that the potential extra gets
        // are worth *not* having to synchronize.  If this turns out to be
        // an incorrect assumption, we can add an atomic variable and use
        // a fetchAdd to decide which task does the update.
        if myLocArr.locRAD.RAD(rlocIdx).blk == SENTINEL {
          myLocArr.locRAD.RAD(rlocIdx) = locArr(rlocIdx).myElems._value.dsiGetRAD();
        }
      }
      pragma "no copy" pragma "no auto destroy" var myLocRAD = myLocArr.locRAD;
      pragma "no copy" pragma "no auto destroy" var radata = myLocRAD.RAD;
      if radata(rlocIdx).shiftedData != nil {
        var dataIdx = radata(rlocIdx).getDataIndex_VB(myLocArr.stridable, i);
        return radata(rlocIdx).shiftedData(dataIdx);
      }
    }
  }
  return locArr(dom.dist.targetLocsIdx(i))(i);
}

proc VariBlockArr.dsiAccess(i: idxType...rank) ref
  return dsiAccess(i);

iter VariBlockArr.these() ref {
  for i in dom do
    yield dsiAccess(i);
}


//
// TODO: Rewrite this to reuse more of the global domain iterator
// logic?  (e.g., can we forward the forall to the global domain
// somehow?
//
iter VariBlockArr.these(param tag: iterKind) where tag == iterKind.leader {
  for followThis in dom.these(tag) do {
    yield followThis;
  }
}

proc VariBlockArr.dsiStaticFastFollowCheck(type leadType) param
  return leadType == this.type || leadType == this.dom.type;

proc VariBlockArr.dsiDynamicFastFollowCheck(lead: [])
  return lead.domain._value == this.dom;

proc VariBlockArr.dsiDynamicFastFollowCheck(lead: domain)
  return lead._value == this.dom;

iter VariBlockArr.these(param tag: iterKind, followThis, param fast: bool = false) ref where tag == iterKind.follower {
  proc anyStridable(rangeTuple, param i: int = 1) param
      return if i == rangeTuple.size then rangeTuple(i).stridable
             else rangeTuple(i).stridable || anyStridable(rangeTuple, i+1);

  if chpl__testParFlag {
    if fast then
      chpl__testPar("VariBlock array fast follower invoked on ", followThis);
    else
      chpl__testPar("VariBlock array non-fast follower invoked on ", followThis);
  }

  if testFastFollowerOptimization then
    writeln((if fast then "fast" else "regular") + " follower invoked for VariBlock array");

  var myFollowThis: rank*range(idxType=idxType, stridable=stridable || anyStridable(followThis));
  var lowIdx: rank*idxType;

  for param i in 1..rank {
    var stride = dom.whole.dim(i).stride;
    // NOTE: Not bothering to check to see if these can fit into idxType
    var low = followThis(i).low * abs(stride):idxType;
    var high = followThis(i).high * abs(stride):idxType;
    myFollowThis(i) = (low..high by stride) + dom.whole.dim(i).low by followThis(i).stride;
    lowIdx(i) = myFollowThis(i).low;
  }

  if fast {
    //
    // TODO: The following is a buggy hack that will only work when we're
    // distributing across the entire Locales array.  I still think the
    // locArr/locDoms arrays should be associative over locale values.
    //
    var arrSection = locArr(dom.dist.targetLocsIdx(lowIdx));

    //
    // if arrSection is not local and we're using the fast follower,
    // it means that myFollowThisDom is empty; make arrSection local so
    // that we can use the local block below
    //
    if arrSection.locale.id != here.id then
      arrSection = myLocArr;
    local {
      for e in arrSection.myElems((...myFollowThis)) do
        yield e;
    }
  } else {
    //
    // we don't necessarily own all the elements we're following
    //
    proc accessHelper(i) ref {
      if myLocArr then local {
        if myLocArr.locDom.member(i) then
          return myLocArr.this(i);
      }
      return dsiAccess(i);
    }
    const myFollowThisDom = {(...myFollowThis)};
    for i in myFollowThisDom {
      yield accessHelper(i);
    }
  }
}

//
// output array
//
proc VariBlockArr.dsiSerialWrite(f: Writer) {
  type strType = chpl__signedType(idxType);
  var binary = f.binary();
  if dom.dsiNumIndices == 0 then return;
  var i : rank*idxType;
  for dim in 1..rank do
    i(dim) = dom.dsiDim(dim).low;
  label next while true {
    f.write(dsiAccess(i));
    if i(rank) <= (dom.dsiDim(rank).high - dom.dsiDim(rank).stride:strType) {
      if ! binary then f.write(" ");
      i(rank) += dom.dsiDim(rank).stride:strType;
    } else {
      for dim in 1..rank-1 by -1 {
        if i(dim) <= (dom.dsiDim(dim).high - dom.dsiDim(dim).stride:strType) {
          i(dim) += dom.dsiDim(dim).stride:strType;
          for dim2 in dim+1..rank {
            f.writeln();
            i(dim2) = dom.dsiDim(dim2).low;
          }
          continue next;
        }
      }
      break;
    }
  }
}

proc VariBlockArr.dsiSlice(d: VariBlockDom) {
  var alias = new VariBlockArr(policyType=policyType, eltType=eltType, rank=rank, idxType=idxType, stridable=d.stridable, dom=d);
  var thisid = this.locale.id;
  coforall i in d.dist.targetLocDom {
    on d.dist.targetLocales(i) {
      alias.locArr[i] = new LocVariBlockArr(eltType=eltType, rank=rank, idxType=idxType, stridable=d.stridable, locDom=d.locDoms[i], myElems=>locArr[i].myElems[d.locDoms[i].myVariBlock]);
      if thisid == here.id then
        alias.myLocArr = alias.locArr[i];
    }
  }
  if doRADOpt then alias.setupRADOpt();
  return alias;
}

proc VariBlockArr.dsiLocalSlice(ranges) {
  var low: rank*idxType;
  for param i in 1..rank {
    low(i) = ranges(i).low;
  }
  var A => locArr(dom.dist.targetLocsIdx(low)).myElems((...ranges));
  return A;
}



proc VariBlockArr.dsiReallocate(d: domain) {
  //
  // For the default rectangular array, this function changes the data
  // vector in the array class so that it is setup once the default
  // rectangular domain is changed.  For this distributed array class,
  // we don't need to do anything, because changing the domain will
  // change the domain in the local array class which will change the
  // data in the local array class.  This will only work if the domain
  // we are reallocating to has the same distribution, but domain
  // assignment is defined so that only the indices are transferred.
  // The distribution remains unchanged.
  //
}

proc VariBlockArr.dsiPostReallocate() {
  // Call this *after* the domain has been reallocated
  if doRADOpt then setupRADOpt();
}

proc VariBlockArr.setRADOpt(val=true) {
  doRADOpt = val;
  if doRADOpt then setupRADOpt();
}

//
// the accessor for the local array -- assumes the index is local
//
proc LocVariBlockArr.this(i) ref {
  return myElems(i);
}

//
// Privatization
//
proc VariBlock.VariBlock(other: VariBlock, privateData,
                param rank = other.rank,
                type idxType = other.idxType,
                policy = other.policy) {
  boundingBox = {(...privateData(1))};
  targetLocDom = {(...privateData(2))};
  dataParTasksPerLocale = privateData(3);
  dataParIgnoreRunningTasks = privateData(4);
  dataParMinGranularity = privateData(5);
  timer = privateData(6);
  indexer = policy.makeIndexer();
  for i in targetLocDom {
    targetLocales(i) = other.targetLocales(i);
    locDist(i) = other.locDist(i);
  }
}

proc VariBlock.dsiSupportsPrivatization() param return true;

proc VariBlock.dsiGetPrivatizeData() {
  return (boundingBox.dims(), targetLocDom.dims(),
          dataParTasksPerLocale, dataParIgnoreRunningTasks, dataParMinGranularity, timer );
}

proc VariBlock.dsiPrivatize(privatizeData) {
  return new VariBlock(this, privatizeData);
}

proc VariBlock.dsiGetReprivatizeData() return boundingBox.dims();

proc VariBlock.dsiReprivatize(other, reprivatizeData) {
  boundingBox = {(...reprivatizeData)};
  targetLocDom = other.targetLocDom;
  targetLocales = other.targetLocales;
  locDist = other.locDist;
  dataParTasksPerLocale = other.dataParTasksPerLocale;
  dataParIgnoreRunningTasks = other.dataParIgnoreRunningTasks;
  dataParMinGranularity = other.dataParMinGranularity;
  policy = other.policy;
}

proc VariBlockDom.dsiSupportsPrivatization() param return true;

proc VariBlockDom.dsiGetPrivatizeData() return (dist.pid, whole.dims());

proc VariBlockDom.dsiPrivatize(privatizeData) {
  var privdist = chpl_getPrivatizedCopy(dist.type, privatizeData(1));
  var c = new VariBlockDom(policyType=policyType, rank=rank, idxType=idxType, stridable=stridable, dist=privdist, timer=timer);
  for i in c.dist.targetLocDom do
    c.locDoms(i) = locDoms(i);
  c.whole = {(...privatizeData(2))};
  return c;
}

proc VariBlockDom.dsiGetReprivatizeData() return whole.dims();

proc VariBlockDom.dsiReprivatize(other, reprivatizeData) {
  for i in dist.targetLocDom do
    locDoms(i) = other.locDoms(i);
  whole = {(...reprivatizeData)};
}

proc VariBlockArr.dsiSupportsPrivatization() param return true;

proc VariBlockArr.dsiGetPrivatizeData() return dom.pid;

proc VariBlockArr.dsiPrivatize(privatizeData) {
  var privdom = chpl_getPrivatizedCopy(dom.type, privatizeData);
  var c = new VariBlockArr(policyType=policyType, eltType=eltType, rank=rank, idxType=idxType, stridable=stridable, dom=privdom);
  for localeIdx in c.dom.dist.targetLocDom {
    c.locArr(localeIdx) = locArr(localeIdx);
    if c.locArr(localeIdx).locale.id == here.id then
      c.myLocArr = c.locArr(localeIdx);
  }
  return c;
}

proc VariBlockArr.dsiSupportsBulkTransfer() param return true;
proc VariBlockArr.dsiSupportsBulkTransferInterface() param return true;

proc VariBlockArr.doiCanBulkTransfer() {
  if debugVariBlockDistBulkTransfer then
    writeln("In VariBlockArr.doiCanBulkTransfer");

  if dom.stridable then
    for param i in 1..rank do
      if dom.whole.dim(i).stride != 1 then return false;

  // See above note regarding aliased arrays
  if disableAliasedBulkTransfer then
    if _arrAlias != nil then return false;

  return true;
}

proc VariBlockArr.doiCanBulkTransferStride() param {
  if debugVariBlockDistBulkTransfer then
    writeln("In VariBlockArr.doiCanBulkTransferStride");

  // A VariBlockArr is a bunch of DefaultRectangular arrays,
  // so strided bulk transfer gotta be always possible.
  return true;
}

proc VariBlockArr.doiBulkTransfer(B) {
  if debugVariBlockDistBulkTransfer then
    writeln("In VariBlockArr.doiBulkTransfer");

  if debugVariBlockDistBulkTransfer then resetCommDiagnostics();
  var sameDomain: bool;
  // We need to do the following on the locale where 'this' was allocated,
  //  but hopefully, most of the time we are initiating the transfer
  //  from the same locale (local on clauses are optimized out).
  on this do sameDomain = dom==B._value.dom;
  // Use zippered iteration to piggyback data movement with the remote
  //  fork.  This avoids remote gets for each access to locArr[i] and
  //  B._value.locArr[i]
  coforall (i, myLocArr, BmyLocArr) in zip(dom.dist.targetLocDom,
                                        locArr,
                                        B._value.locArr) do
    on dom.dist.targetLocales(i) {

    if sameDomain &&
      chpl__useBulkTransfer(myLocArr.myElems, BmyLocArr.myElems) {
      // Take advantage of DefaultRectangular bulk transfer
      if debugVariBlockDistBulkTransfer then startCommDiagnosticsHere();
      local {
        myLocArr.myElems._value.doiBulkTransfer(BmyLocArr.myElems);
      }
      if debugVariBlockDistBulkTransfer then stopCommDiagnosticsHere();
    } else {
      if debugVariBlockDistBulkTransfer then startCommDiagnosticsHere();
      if (rank==1) {
        var lo=dom.locDoms[i].myVariBlock.low;
        const start=lo;
        //use divCeilPos(i,j) to know the limits
        //but i and j have to be positive.
        for (rid, rlo, size) in ConsecutiveChunks_VB(dom,B._value.dom,i,start) {
          if debugVariBlockDistBulkTransfer then writeln("Local Locale id=",i,
                                            "; Remote locale id=", rid,
                                            "; size=", size,
                                            "; lo=", lo,
                                            "; rlo=", rlo
                                            );
          // NOTE: This does not work with --heterogeneous, but heterogeneous
          // compilation does not work right now.  This call should be changed
          // once that is fixed.
          var dest = myLocArr.myElems._value.theData;
          const src = B._value.locArr[rid].myElems._value.theData;
          __primitive("chpl_comm_get",
                      __primitive("array_get", dest,
                                  myLocArr.myElems._value.getDataIndex(lo)),
                      rid,
                      __primitive("array_get", src,
                                  B._value.locArr[rid].myElems._value.getDataIndex(rlo)),
                      size);
          lo+=size;
        }
      } else {
        var orig=dom.locDoms[i].myVariBlock.low(dom.rank);
        for coord in dropDims_VB(dom.locDoms[i].myVariBlock, dom.locDoms[i].myVariBlock.rank) {
          var lo=if rank==2 then (coord,orig) else ((...coord), orig);
          const start=lo;
          for (rid, rlo, size) in ConsecutiveChunksD_VB(dom,B._value.dom,i,start) {
            if debugVariBlockDistBulkTransfer then writeln("Local Locale id=",i,
                                        "; Remote locale id=", rid,
                                        "; size=", size,
                                        "; lo=", lo,
                                        "; rlo=", rlo
                                        );
          var dest = myLocArr.myElems._value.theData;
          const src = B._value.locArr[rid].myElems._value.theData;
          __primitive("chpl_comm_get",
                      __primitive("array_get", dest,
                                  myLocArr.myElems._value.getDataIndex(lo)),
                      dom.dist.targetLocales(rid).id,
                      __primitive("array_get", src,
                                  B._value.locArr[rid].myElems._value.getDataIndex(rlo)),
                      size);
            lo(rank)+=size;
          }
        }
      }
      if debugVariBlockDistBulkTransfer then stopCommDiagnosticsHere();
    }
  }
  if debugVariBlockDistBulkTransfer then writeln("Comms:",getCommDiagnostics());
}

proc VariBlockArr.dsiTargetLocales() {
  return dom.dist.targetLocales;
}

// VariBlock subdomains are continuous

proc VariBlockArr.dsiHasSingleLocalSubdomain() param return true;

// returns the current locale's subdomain

proc VariBlockArr.dsiLocalSubdomain() {
  return myLocArr.locDom.myVariBlock;
}

iter ConsecutiveChunks_VB(d1,d2,lid,lo) {
  var elemsToGet = d1.locDoms[lid].myVariBlock.numIndices;
  const offset   = d2.whole.low - d1.whole.low;
  var rlo=lo+offset;
  var rid  = d2.dist.targetLocsIdx(rlo);
  while (elemsToGet>0) {
    const size = min(d2.numRemoteElems(rlo,rid),elemsToGet):int;
    yield (rid,rlo,size);
    rid +=1;
    rlo += size;
    elemsToGet -= size;
  }
}

iter ConsecutiveChunksD_VB(d1,d2,i,lo) {
  const rank=d1.rank;
  var elemsToGet = d1.locDoms[i].myVariBlock.dim(rank).length;
  const offset   = d2.whole.low - d1.whole.low;
  var rlo = lo+offset;
  var rid = d2.dist.targetLocsIdx(rlo);
  while (elemsToGet>0) {
    const size = min(d2.numRemoteElems(rlo(rank):int,rid(rank):int),elemsToGet);
    yield (rid,rlo,size);
    rid(rank) +=1;
    rlo(rank) += size;
    elemsToGet -= size;
  }
}

proc VariBlockDom.numRemoteElems(rlo,rid){
  // NOTE: Not bothering to check to see if rid+1, length, or rlo-1 used
  //  below can fit into idxType
  var blo,bhi:dist.idxType;
  if rid==(dist.targetLocDom.dim(rank).length - 1) then
    bhi=whole.dim(rank).high;
  else
      bhi=dist.boundingBox.dim(rank).low +
        intCeilXDivByY((dist.boundingBox.dim(rank).high - dist.boundingBox.dim(rank).low +1)*(rid+1):idxType,
                       dist.targetLocDom.dim(rank).length:idxType) - 1:idxType;

  return(bhi - (rlo - 1):idxType);
}

//Brad's utility function. It drops from Domain D the dimensions
//indicated by the subsequent parameters dims.
proc dropDims_VB(D: domain, dims...) {
  var r = D.dims();
  var r2: (D.rank-dims.size)*r(1).type;
  var j = 1;
  for i in 1..D.rank do
    for k in 1..dims.size do
      if dims(k) != i {
        r2(j) = r(i);
        j+=1;
      }
  var DResult = {(...r2)};
  return DResult;
}

//For assignments of the form: "any = VariBlock"
//Currently not used, instead we use: doiBulkTransferFrom()
proc VariBlockArr.doiBulkTransferTo(Barg)
{
  if debugVariBlockDistBulkTransfer then
    writeln("In VariBlockArr.doiBulkTransferTo()");
  
  const B = this, A = Barg._value;
  type el = B.idxType;
  coforall i in B.dom.dist.targetLocDom do // for all locales
    on B.dom.dist.targetLocales(i)
      {
        var regionB = B.dom.locDoms(i).myVariBlock;
        if regionB.numIndices>0
        {
          const ini=bulkCommConvertCoordinate(regionB.first, B, A);
          const end=bulkCommConvertCoordinate(regionB.last, B, A);
          const sa=chpl__tuplify(A.dom.locDoms(i).myVariBlock.stride);
          
          var r1,r2: rank * range(idxType = el,stridable = true);
          r2=regionB.dims();
           //In the case that the number of elements in dimension t for r1 and r2
           //were different, we need to calculate the correct stride in r1
          for param t in 1..rank{
            r1[t] = (ini[t]:el..end[t]:el by sa[t]:el);
            if r1[t].length != r2[t].length then
              r1[t] = (ini[t]:el..end[t]:el by (end[t] - ini[t]):el/(r2[t].length-1));
          }
        
          if debugVariBlockDistBulkTransfer then
            writeln("A",(...r1),".FromDR",regionB);
    
          Barg[(...r1)]._value.doiBulkTransferFromDR(B.locArr[i].myElems);
        }
      }
}

//For assignments of the form: "VariBlock = any" 
//where "any" means any array that implements the bulk transfer interface
proc VariBlockArr.doiBulkTransferFrom(Barg)
{
  if debugVariBlockDistBulkTransfer then
    writeln("In VariBlockArr.doiBulkTransferFrom()");
 
  const A = this, B = Barg._value;
  type el = A.idxType;
  coforall i in A.dom.dist.targetLocDom do // for all locales
    on A.dom.dist.targetLocales(i)
    {
      var regionA = A.dom.locDoms(i).myVariBlock;
      if regionA.numIndices>0
      {
        const ini=bulkCommConvertCoordinate(regionA.first, A, B);
        const end=bulkCommConvertCoordinate(regionA.last, A, B);
        const sb=chpl__tuplify(B.dom.locDoms(i).myVariBlock.stride);
        
        var r1,r2: rank * range(idxType = el,stridable = true);
        r2=regionA.dims();
         //In the case that the number of elements in dimension t for r1 and r2
         //were different, we need to calculate the correct stride in r1
        for param t in 1..rank{
            r1[t] = (ini[t]:el..end[t]:el by sb[t]:el);
            if r1[t].length != r2[t].length then
              r1[t] = (ini[t]:el..end[t]:el by (end[t] - ini[t]):el/(r2[t].length-1));
        }
      
        if debugVariBlockDistBulkTransfer then
            writeln("B{",(...r1),"}.ToDR",regionA);
   
        Barg[(...r1)]._value.doiBulkTransferToDR(A.locArr[i].myElems[regionA]);
      }
    }
}
 
//For assignments of the form: DR = VariBlock 
//(default rectangular array = block distributed array)
proc VariBlockArr.doiBulkTransferToDR(Barg)
{
  if debugVariBlockDistBulkTransfer then
    writeln("In VariBlockArr.doiBulkTransferToDR()");

  const A = this, B = Barg._value; //Always it is a DR
  type el = A.idxType;
  coforall j in A.dom.dist.targetLocDom do
    on A.dom.dist.targetLocales(j)
    {
      const inters=A.dom.locDoms(j).myVariBlock;
      if(inters.numIndices>0)
      {
        const ini=bulkCommConvertCoordinate(inters.first, A, B);
        const end=bulkCommConvertCoordinate(inters.last, A, B);
        const sa = chpl__tuplify(B.dom.dsiStride);
  
        var r1,r2: rank * range(idxType = el,stridable = true);
        for param t in 1..rank
        {
          r2[t] = (chpl__tuplify(inters.first)[t]
                   ..chpl__tuplify(inters.last)[t]
                   by chpl__tuplify(inters.stride)[t]);
          r1[t] = (ini[t]:el..end[t]:el by sa[t]:el);
        }
        
        if debugVariBlockDistBulkTransfer then
          writeln("A[",r1,"] = B[",r2,"]");
      
        const d ={(...r1)};
        const slice = B.dsiSlice(d._value);
        //Necessary to calculate the value of blk variable in DR
        //with the new domain r1
        slice.adjustBlkOffStrForNewDomain(d._value, slice);
        
        slice.doiBulkTransferStride(A.locArr[j].myElems[(...r2)]._value);
        
        delete slice;
      }
    }
}

//For assignments of the form: VariBlock = DR 
//(block distributed array = default rectangular)
proc VariBlockArr.doiBulkTransferFromDR(Barg) 
{
  if debugVariBlockDistBulkTransfer then
    writeln("In VariBlockArr.doiBulkTransferFromDR");

  const A = this, B = Barg._value;
  type el = A.idxType;
  coforall j in A.dom.dist.targetLocDom do
    on A.dom.dist.targetLocales(j)
    {
      const inters=A.dom.locDoms(j).myVariBlock;
      if(inters.numIndices>0)
      {
        const ini=bulkCommConvertCoordinate(inters.first, A, B);
        const end=bulkCommConvertCoordinate(inters.last, A, B);
        const sb = chpl__tuplify(B.dom.dsiStride);
        
        var r1,r2: rank * range(idxType = el,stridable = true);
        for param t in 1..rank
        {
          r2[t] = (chpl__tuplify(inters.first)[t]
                   ..chpl__tuplify(inters.last)[t]
                   by chpl__tuplify(inters.stride)[t]);
          r1[t] = (ini[t]:el..end[t]:el by sb[t]:el);
        }
        
        if debugVariBlockDistBulkTransfer then
          writeln("A[",r2,"] = B[",r1,"]");
          
        const d ={(...r1)};
        const slice = B.dsiSlice(d._value);
        //this step it's necessary to calculate the value of blk variable in DR
        //with the new domain r1
        slice.adjustBlkOffStrForNewDomain(d._value, slice);
        
        A.locArr[j].myElems[(...r2)]._value.doiBulkTransferStride(slice);
        delete slice;
      }
    }
}
