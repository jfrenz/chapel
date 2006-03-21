record history_float {
  param size : int;
  var h : (size*float);
  var f : float;
}

fun =(x : history_float, y : float) {
  for i in 2..x.size by -1 do
    x.h(i) = x.h(i-1);
  x.h(1) = x.f;
  x.f = y;
  return x;
}

fun >(x : history_float, y : float) {
  return x.f > y;
}

fun +(x : history_float, y : float) {
  return x.f + y;
}

fun fwrite(f : file, x : history_float) {
  fwrite(f, x.f, " (");
  for i in 1..x.size do
    fwrite(f, x.h(i), if i < x.size then ", " else ")");
}
