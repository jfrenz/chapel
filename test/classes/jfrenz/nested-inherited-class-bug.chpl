
class Outer {
    class NestedBase {
        var fieldOne: real;
    }
    
    class NestedDerived: NestedBase {
        var anotherField: int;
    }
}

writeln("It works!");
