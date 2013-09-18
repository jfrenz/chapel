extern proc chpl_task_getSubLoc(): chpl_sublocID_t;
extern proc chpl_task_getRequestedSubLoc(): chpl_sublocID_t;

for loc in Locales do on loc {
  if chpl_task_getRequestedSubLoc() != c_sublocid_any then
    writeln("[", here.id,
            "] Wrong subloc (wanted ", c_sublocid_any,
            ", got ", chpl_task_getSubLoc(), ")");

  for i in 0..#(here:LocaleModel).numSubLocales do
    on (here:LocaleModel).getChild(i) do
      if i!=chpl_task_getSubLoc() then
        writeln("[", here.id,
                "] Wrong subloc (wanted ", i,
                ", got ", chpl_task_getSubLoc(), ")");
}
