/*
  Copyright 2004 John Plevyak, All Rights Reserved, see COPYRIGHT file
*/

#include "geysa.h"
#include "analysis.h"
#include "expr.h"
#include "files.h"
#include "link.h"
#include "misc.h"
#include "stmt.h"
#include "stringutil.h"
#include "symtab.h"
#include "builtin.h"
#include "if1.h"

ASymbol::ASymbol() : xsymbol(0) {
}

AInfo::AInfo() : xast(0) {
}

char *AInfo::pathname() { 
  return xast->filename;
}

int AInfo::line() {
  return xast->lineno;
}

Sym *AInfo::symbol() {
  return NULL;
}

AST *AInfo::copy(Map<PNode *, PNode*> *nmap) {
  return NULL;
}

static void
close_symbols(BaseAST *a, Vec<BaseAST *> &syms) {
  Vec<BaseAST *> set;
  set.set_add(a);
  syms.add(a);
  forv_BaseAST(s, syms) {
    Vec<BaseAST *> moresyms;
    s->getBaseASTs(moresyms);
    forv_BaseAST(ss, moresyms) {
      assert(ss);
      if (set.set_add(ss))
        syms.add(ss);
    }
  }
}

static void
map_symbols(Vec<BaseAST *> &syms) {
  int symbols = 0, types = 0, exprs = 0, stmts = 0;
  if (verbose_level > 1)
    printf("map_symbols: %d\n", syms.n);
  forv_BaseAST(s, syms) {
    Symbol *sym = dynamic_cast<Symbol *>(s);
    if (sym) {
      sym->asymbol = new ASymbol;
      sym->asymbol->xsymbol = sym;
      symbols++;
      if (verbose_level > 1 && sym->name)
        printf("map_symbols: found Symbol '%s'\n", sym->name);
    } else {
      Type *t = dynamic_cast<Type *>(s);
      if (t) {
	t->asymbol = new ASymbol;
	t->asymbol->xsymbol = t;
	types++;
      } else {
	Expr *e = dynamic_cast<Expr *>(s);
	if (e) {
	  e->ainfo = new AInfo;
	  e->ainfo->xast = e;
	  exprs++;
	} else {
	  Stmt *st = dynamic_cast<Stmt *>(s);
	  st->ainfo = new AInfo;
	  st->ainfo->xast = s;
	  stmts++;
	}
      }
    }
  }
  if (verbose_level > 1)
    printf("map_symbols: BaseASTs: %d, Symbols: %d, Types: %d, Exprs: %d, Stmts: %d\n", 
	   syms.n, symbols, types, exprs, stmts);
}

static void 
build_record_type(Type *t, Sym *parent = 0) {
  t->asymbol->type_kind = Type_RECORD;
  if (parent) {
    t->asymbol->implements.add(parent);
    t->asymbol->includes.add(parent);
  }
}

static void
build_enum_element(Sym *ss) {
  ss->type_kind = Type_PRIMITIVE;
  ss->implements.add(sym_enum_element);
  ss->includes.add(sym_enum_element);
}

static void
build_types(Vec<BaseAST *> &syms) {
  Vec<Type *> types;
  forv_BaseAST(s, syms) {
    Type *t = dynamic_cast<Type *>(s);
    if (t) 
      types.add(t);
  }
  forv_Type(t, types) {
    switch (t->astType) {
      default: assert(!"case");
      case TYPE_NULL:
	t->asymbol->type_kind = Type_UNKNOWN;
	break;
      case TYPE_BUILTIN:
	if (t == dtVoid) {
	  t->asymbol->type_kind = Type_ALIAS;
	  t->asymbol->alias = sym_void;
	} else if (t == dtBoolean) {
	  t->asymbol->type_kind = Type_ALIAS;
	  t->asymbol->alias = sym_bool;
	} else if (t == dtInteger) {
	  t->asymbol->type_kind = Type_ALIAS;
	  t->asymbol->alias = sym_int;
	} else if (t == dtFloat) {
	  t->asymbol->type_kind = Type_ALIAS;
	  t->asymbol->alias = sym_float;
	} else if (t == dtFloat) {
	  t->asymbol->type_kind = Type_ALIAS;
	  t->asymbol->alias = sym_float;
	} else if (t == dtString) {
	  t->asymbol->type_kind = Type_ALIAS;
	  t->asymbol->alias = sym_string;
	} else
	  t->asymbol->type_kind = Type_UNKNOWN;
	break;
      case TYPE_ENUM: {
	t->asymbol->type_kind = Type_TAGGED;
	Vec<BaseAST *> syms;
	t->getSymbols(syms);
	forv_BaseAST(s, syms) {
	  Sym *ss = dynamic_cast<Symbol*>(s)->asymbol;
	  build_enum_element(ss);
	  t->asymbol->has.add(ss);
	}
	break;
      }
      case TYPE_DOMAIN: build_record_type(t, sym_domain); break;
      case TYPE_INDEX: build_record_type(t, sym_tuple); break;
      case TYPE_SUBDOMAIN: build_record_type(t, sym_domain); break;
      case TYPE_SUBINDEX: build_record_type(t, sym_tuple); break;
      case TYPE_ARRAY: build_record_type(t, sym_array); break;
      case TYPE_USER: {
	UserType *tt = dynamic_cast<UserType*>(t);
	t->asymbol->type_kind = Type_ALIAS;
	t->asymbol->alias = tt->definition->asymbol;
	break;
      }
      case TYPE_CLASS: {
	ClassType *tt = dynamic_cast<ClassType*>(t);
	t->asymbol->type_kind = Type_RECORD;
	t->asymbol->implements.add(tt->parentClass->asymbol);
	t->asymbol->includes.add(tt->parentClass->asymbol);
	break;
      }
    }
  }
}

static Sym *
new_sym(char *name) {
  return if1_alloc_sym(if1, name);
}

static void
new_primitive_type(Sym *&sym, char *name) {
  if (!sym)
    sym = new_sym(name);
  sym->type_kind = Type_PRIMITIVE;
}

static void
new_alias_type(Sym *&sym, char *name, Sym *alias) {
  if (!sym)
    sym = new_sym(name);
  sym->type_kind = Type_ALIAS;
  sym->alias = alias;
}

static void
new_sum_type(Sym *&sym, char *name, ...)  {
  if (!sym)
    sym = new_sym(name);
  sym->type_kind = Type_SUM;
  va_list ap;
  va_start(ap, name);
  Sym *s = 0;
  do {
    if ((s = va_arg(ap, Sym*)))
      sym->has.add(s);
  } while (s);
}

static void
new_global_variable(Sym *&sym, char *name) {
  if (!sym)
    sym = new_sym(name);
  sym->global_scope = 1;
}

static void
new_symbol(Sym *&sym, char *name) {
  if (!sym)
    sym = if1_make_symbol(if1, name);
}

static void
build_builtin_symbols() {
  if (!sym_system)
    sym_system = new_sym("system");
  if (!sym_system->init)
    sym_system->init = new_sym("__init");
  build_module(sym_system, sym_system->init);

  new_primitive_type(sym_anyclass, "anyclass");
  sym_anyclass->type_sym = sym_anyclass;
  
  new_primitive_type(sym_any, "any");
  new_primitive_type(sym_module, "module");
  new_primitive_type(sym_symbol, "symbol");
  if1_set_symbols_type(if1);
  new_primitive_type(sym_function, "function");
  new_primitive_type(sym_continuation, "continuation");
  new_primitive_type(sym_vector, "vector");
  new_primitive_type(sym_tuple, "tuple");
  new_primitive_type(sym_void, "void");
  if (!sym_object)
    sym_object = new_sym("object");
  sym_object->type_kind = Type_RECORD;
  new_primitive_type(sym_list, "list");
  new_primitive_type(sym_ref, "ref");
  new_primitive_type(sym_value, "value");
  new_primitive_type(sym_catagory, "catagory");
  new_primitive_type(sym_set, "set");
  new_primitive_type(sym_sequence, "sequence");
  new_primitive_type(sym_domain, "domain");
  new_primitive_type(sym_array, "array");
  new_primitive_type(sym_int8, "int8");
  new_primitive_type(sym_int16, "int16");
  new_primitive_type(sym_int32, "int32");
  new_primitive_type(sym_int64, "int64");
  new_alias_type(sym_int, "int", sym_int64);
  new_primitive_type(sym_uint8, "uint8");
  new_primitive_type(sym_uint16, "uint16");
  new_primitive_type(sym_uint32, "uint32");
  new_primitive_type(sym_uint64, "uint64");
  new_alias_type(sym_uint, "uint", sym_uint64);
  new_sum_type(sym_anyint, "anyint", 
	       sym_int8, sym_int16, sym_int32, sym_int64,
	       sym_uint8, sym_uint16, sym_uint32, sym_uint64, 0);
  new_primitive_type(sym_size, "size");
  new_alias_type(sym_bool, "bool", sym_int);
  new_primitive_type(sym_enum_element, "enum_element");
  new_primitive_type(sym_float32, "float32");
  new_primitive_type(sym_float64, "float64");
  new_primitive_type(sym_float80, "float80");
  new_primitive_type(sym_float128, "float128");
  new_primitive_type(sym_float, "float");
  new_sum_type(sym_anyfloat, "anyfloat", 
	       sym_float32, sym_float64, sym_float80, sym_float128, 0);
  new_primitive_type(sym_anynum, "anynum");
  new_primitive_type(sym_char, "char");
  new_primitive_type(sym_string, "string");
  if1_set_symbols_type(if1);
  
  new_global_variable(sym_null, "null");
  new_symbol(sym_reply, "reply");
  new_symbol(sym_make_tuple, "make_tuple");
  new_symbol(sym_make_vector, "make_vector");
  new_symbol(sym_make_list, "make_list");
  new_symbol(sym_make_continuation, "make_continuation");
  new_symbol(sym_make_set, "make_set");
  new_symbol(sym_new, "new");
  new_symbol(sym_new_object, "new_object");
  new_symbol(sym_index, "index");
  new_symbol(sym_primitive, "primitive");
  new_symbol(sym_operator, "operator");
  new_symbol(sym_print, "print");
  new_symbol(sym_destruct, "destruct");
  new_symbol(sym_meta_apply, "meta_apply");
  new_symbol(sym_period, "period");
  new_symbol(sym_assign, "assign");
  new_global_variable(sym_init, "init");
#define S(_n) assert(sym_##_n);
#include "builtin_symbols.h"
#undef S
}

static void
build_functions(Vec<BaseAST *> &syms) {
  Vec<FnSymbol *> fns;
  forv_BaseAST(s, syms)
    if (s->astType == SYMBOL_FN)
      fns.add(dynamic_cast<FnSymbol*>(s)); 
}

static void
import_symbols(BaseAST *a) {
  Vec<BaseAST *> syms;
  close_symbols(a, syms);
  map_symbols(syms);
  build_builtin_symbols();
  build_types(syms);
  build_functions(syms);
}

void
analyze_new_ast(BaseAST* a) {
  import_symbols(a);
}


