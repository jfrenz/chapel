
fun callinout2(inout x: int = 100, inout y: int = 200): int {
  x += 1;
  y += 1;
  writeln("in callinout2, x is: ", x, ", y is: ", y);
  writeln("returning: ", x+y);
  return x+y;
}

fun main() {
  var a: int = 10;
  var b: int = 30;
  var r: int;

  r = callinout2(x=a);
  writeln("at callsite, a is: ", a, ", b is: ", b, ", r is: ", r);
  writeln();

  r = callinout2(y=a);
  writeln("at callsite, a is: ", a, ", b is: ", b, ", r is: ", r);
  writeln();

  r = callinout2(x=a, y=a);
  writeln("at callsite, a is: ", a, ", b is: ", b, ", r is: ", r);
  writeln();

  r = callinout2(y=a, x=a);
  writeln("at callsite, a is: ", a, ", b is: ", b, ", r is: ", r);
  writeln();

  r = callinout2(x=a, y=b);
  writeln("at callsite, a is: ", a, ", b is: ", b, ", r is: ", r);
  writeln();

  r = callinout2(x=b, y=a);
  writeln("at callsite, a is: ", a, ", b is: ", b, ", r is: ", r);
  writeln();
}
