// contains functions to move atoms and build neighbor lists

use initMD;

// update ghost information
proc updateFluff() {
  Pos.updateFluff();
  Count.updateFluff();

  // offset positions if needed
  coforall idx in LocaleGridDom {
    on LocaleGrid[idx] {
      for (Section, Offset) in zip(Pos.boundaries(), PosOffset[idx]) {
          if Offset != (0.0,0.0,0.0) {
            for (p,c) in zip(Pos.localSlice(Section), Count.localSlice(Section)) {
              p[1..c] += Offset;
            }
          }
      }
    }
  }
}

// if atoms moved outside the box, wrap them around 
proc pbc() {
  forall (pos, c) in zip(Pos, Count) {
    for x in pos[1..c] {
      for i in 1..3 {
        if x(i) < 0 then x(i) += box(i);
        else if x(i) >= box(i) then x(i) -= box(i);
      }
    }
  }
}

// put atoms into correct bins and rebuild neighbor lists
proc buildNeighbors() {
  if debug then writeln("starting to build...");

  var neighTimer : Timer;
  neighTimer.start();
 
  // enforce boundaries
  pbc();

  commTime += neighTimer.elapsed();
  neighTimer.stop();
  neighTimer.clear();
  neighTimer.start();

  // if any atoms moved outside a bin, relocate
  binAtoms();

  buildTime += neighTimer.elapsed();
  neighTimer.stop();
  neighTimer.clear();
  neighTimer.start();

  if debug then writeln("starting comms...");

  // grab ghost/overlapping atoms
  updateFluff();

  if debug then writeln("comms done...");

  commTime += neighTimer.elapsed();
  neighTimer.stop();
  neighTimer.clear();
  neighTimer.start();

  forall (bin, pos, r, c) in zip(Bins, Pos, binSpace, Count) {
    const existing = 1..c;
    for (a, p, i) in zip(bin[existing], pos[existing], existing) {
      a.ncount = 0;

      for s in stencil {
        const o = r + s;
        const existing = 1..Count[o];

        for (n, x) in zip(Pos[o][existing], existing) {
          if r == o && x == i then continue; 

          // are we within range?
          const del = p - n;
          const rsq = dot(del,del);
          if rsq <= cutneighsq {
            a.ncount += 1;

            // resize neighbor list if necessary
            var h = a.nspace.high;
            while a.ncount > h { 
              if debug then writeln("NSPACE RESIZE");
              h = ((a.nspace.high*1.2) : int);
              a.nspace = {1..h};
            }
            // store atom's bin and index
            a.neighs[a.ncount] = (o,x);
          }
          
        }
      }
    }
  }

  buildTime += neighTimer.elapsed();

  if debug then writeln("building done...");
} // end of buildNeighbors

// add an atom 'a' to bin 'b'
// resize if necessary
inline proc addatom(a : atom, x : v3, b : v3int) {
  // increment bin's # of atoms
  Count[b] += 1;

  // a little odd, but necessary to do comms here...
  const end = Count.readRemote(b);
  
  // resize bin storage if needed
  if end >= perBinSpace.high {
    if debug then writeln("PERBIN RESIZE");
    var h = (perBinSpace.high * 1.3) : int;
    perBinSpace = {1..h};
  }
 
  // add to the end of the bin
  Bins[b][end] = a;
  Pos[b][end] = x;
}

proc binAtoms() {
  var MSpace : domain(1) = {1..50};
  var MList: [MSpace] (atom, v3, v3int);
  var MCount: int;

  for (bin, pos, r, c) in zip(Bins, Pos, binSpace, Count) {
    var cur = 1;

    // for each atom, check if moved
    // because we move from the end, this setup allows us to examine 
    // the atom pulled from the end
    while(cur <= c) {
      const destBin = coord2bin(pos[cur]);

      // atom moved
      if destBin != r { 
        MCount += 1;

        // resize storage as needed
        if MCount >= MSpace.high then 
          MSpace = {1..MSpace.high * 2};

        MList[MCount] = (bin[cur], pos[cur], destBin);

        // replace with atom at end of list, if one exists
        if cur < c {
          bin[cur] = bin[c]; 
          pos[cur] = pos[c];
        }

        // correct bin count
        c -= 1; 
      } else cur += 1;
    }
  }

  // actually move the atoms
  for (a, x, b) in MList[1..MCount] {
    addatom(a,x,b);
  }
}

// compute atom's correct bin based on its physical position
proc coord2bin(x : v3){
  var cur : v3int;

  // create a simple mask on a per-dimension basis
  var mask : v3int;
  for i in 1..3 do 
    mask(i) = if x(i) >= box(i) then 1 else 0;

  // if the position has drifted outside the physical space, 
  // adjust. Divide position by the size of a bin, and add 
  // (1,1,1) so we're starting at the lowest possible bin
  const temp = (x - box*mask) * bininv + (1,1,1);

  // can't cast from 3*real to 3*int (yet?)
  for i in 1..3 do 
    cur(i) = temp(i) : int;

  return cur;
}