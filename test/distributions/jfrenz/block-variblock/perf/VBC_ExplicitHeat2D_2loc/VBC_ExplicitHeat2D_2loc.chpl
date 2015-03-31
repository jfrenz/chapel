use VbBenchFw;
use Random;

config const xdiv = 128;
config const ydiv = 96;
config const steps = 10;
config const maxval = 99;
config const boundary = 0.0;
config const s = 0.08;

const Space = {0..#(xdiv+2), 0..#(ydiv+2)};
const SpaceIn = {1..#xdiv, 1..#ydiv};

class Prog {
    const dist;
    
    const dom: domain(2) dmapped dist = Space;
    const domIn: subdomain(dom) = SpaceIn;
    
    const A: [dom] real;
    const B: [dom] real;
    var flip: bool;
    
    proc Prog(dist, correctness: bool) {
        if numLocales != 2 then {
            halt("Number of locales must be 2");
        }
        
        //setupArrays(A, B);
    }
    proc run(): bool {
        flip = false;
        
        for s in 1..steps do {
            if ! flip then {
                computeStep(A, B);
            } else {
                computeStep(B, A);
            }
            flip = ! flip;
        }
        
        return true;
    }
    
    proc preRunInfo() {
        writeln("***** INITIAL:");
        printArr(A);
    }
    
    proc postRunInfo() {
        writeln("***** RESULT:");
        if ! flip then {
            printArr(A);
        } else {
            printArr(B);
        }
    }
    
    proc setupArrays(_A, _B) {
        const bdr = boundary;
        _A = boundary;
        _B = boundary;
        
        const rs = new RandomStream(parSafe=false);
        for i in domIn do {
            _A[i] = rs.getNext() * maxval:real;
        }
    }
    
    proc printArr(arr) {
        var tmp: [domIn] int;
        
        forall i in domIn do {
            tmp(i) = round(arr(i)):int;
        }
        
        writeln(tmp);
    }
    
    proc computeStep(initial, result) {
        forall (x,y) in domIn do {
            result(x,y) = (1 - 4*s)*initial(x,y) + s*(initial(x-1,y) + initial(x+1,y) + initial(x,y-1) + initial(x,y+1));
        }
    }
}

class Maker {
    proc this(dist, correctness: bool) {
        return new Prog(dist, correctness: bool);
    }
}

VbBenchRun(new Maker(), Space);
