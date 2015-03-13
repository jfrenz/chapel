use BlockDist;
use VariBlockDist;

const Space = {1..16, 1..12};

const D1: domain(2) dmapped VariBlock(Space) = Space;
const D2: domain(2) dmapped Block(Space) = Space;

var A1: [D1] int;
var A2: [D2] int;

forall (x,y) in D1 do {
    A1(x,y) = x*100 + y;
}

forall (x,y) in D2 do {
    A2(x,y) = (y+1)*121 - x;
}

writeln(A1);
writeln();
writeln(A2);
writeln();
