var x = foo();
var y = -1;

fun main(argc: int) {
  var y = 42;

  writeln("x is: ", x);
  writeln("y is: ", y);  
}

fun foo() {
  writeln("If we see this, I think it worked");
  return 2;
}
