class foo {
  var x : int = 12;
  fun bar(x : int) {
    writeln(x);
  }
}

var f : foo = foo();

f.x = 12;
f.bar(13);
f.bar(f.x);
