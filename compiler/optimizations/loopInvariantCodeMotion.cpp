#include "astutil.h"
#include "bb.h"
#include "passes.h"
#include "stmt.h"
#include "expr.h"
#include "symbol.h"
#include "bitVec.h"
#include "dominator.h"

#include <stack>
#include <set>
#include <algorithm>


#include "view.h"

//#define debugHoisting
#ifdef debugHoisting
  #define printDebug(string) printf string
#else 
 #define printDebug(string) //do nothing
#endif


//#define detailedTiming
#ifdef detailedTiming
  #define startTimer(timer) timer.start()
  #define stopTimer(timer) timer.stop()
#else
  #define startTimer(timer) //do nothing 
  #define stopTimer(timer) //do nothing 
#endif 


Timer allOperandsAreLoopInvariantTimer;
Timer computeAliasTimer;
Timer collectSymExprAndDefTimer;
Timer calculateActualDefsTimer;
Timer buildBBTimer;
Timer computeDominatorTimer;
Timer collectNaturalLoopsTimer;
Timer canPerformCodeMotionTimer;
Timer buildLocalDefMapsTimer;
Timer computeLoopInvariantsTimer;
Timer overallTimer;



//TODO The alias analysis is extremely conservative. Beyond possibly not hoisting 
//things that can be, it is also a performance issue because you have a lot more 
//definitions to consider before declaration something invariant. 

//TODO some other possible optimizations are if you're looking at an outer 
//loop in a nest you can ignore everything inside the inner loop(s) since you 
//already know they can't be hoisted

//TODO Look more into why there are empty basic blocks
 
/*
* This is really just a wrapper for the collection of basic blocks that
* make up a loop. However, it also stores the header, and builds the bit 
* representation as the loop is built to save time. The bit representation
* and the bit representation of the exits can be gotten, putting them 
* in a centralized location. 
*/
class Loop {

  private:
    std::vector<BasicBlock*>* loopBlocks;
    BasicBlock* header;
    BitVec* bitBlocks;
    BitVec* bitExits;

  public: 
    Loop(int nBlocks) {
      loopBlocks = new std::vector<BasicBlock*>;
      bitBlocks = new BitVec(nBlocks); 
      bitExits = new BitVec(nBlocks);
    }
    
    ~Loop() {
      delete loopBlocks;
      loopBlocks = 0;
      delete bitBlocks;
      bitBlocks = 0;
      delete bitExits;
      bitExits = 0;      
    }
    
    // This function exists to place an expr in the 
    // "preheader" of the loop, 
    void insertBefore(Expr* expr) {
      if(header->exprs.size() != 0) {
        if(BlockStmt* blockStmt = toBlockStmt(header->exprs.at(0)->parentExpr)) {
          if(blockStmt->isLoop())
            blockStmt->insertBefore(expr->remove());
        }
      }
    }
    
    //Set the header, and insert the header into the loop blocks
    void setHeader(BasicBlock* setHeader) {
      header = setHeader;
      insertBlock(setHeader);
    }
    
    //add all the blocks from other loop to this loop
    void combine(Loop* otherLoop) {
      for_vector(BasicBlock, block, *otherLoop->getBlocks()) {
        insertBlock(block);
      }
    }
    
    //insert a block and update the bit representation
    void insertBlock(BasicBlock* block) {
      //if this block is already in the loop, do nothing
      if(bitBlocks->test(block->id)) {
        return;
      }
    
      //add the block to the list of blocks and to the bit representation
      loopBlocks->push_back(block);
      bitBlocks->set(block->id);
    }
    
    //check if a block is in the loop based on block id
    bool contains(int i) {
      return bitBlocks->test(i);
    }
    
    //check if a block is in the loop 
    bool contains(BasicBlock* block) {
      return bitBlocks->test(block->id);
    }
    
    //get the header block 
    BasicBlock* getHeader() {
      return header;
    }
    
    //get the actual blocks in the loop 
    std::vector<BasicBlock*>* getBlocks() {
      return loopBlocks;
    }
    
    //get the bitvector that represents the blocks in the loop
    BitVec* getBitBlocks() {
      return bitBlocks;
    }
    
    //get the bitvector that represents the exit blocks
    //the exit blocks are the blocks that have a next basic
    //block that is outside of the loop. 
    BitVec* getBitExits() {    
      bitExits->reset();
      for_vector(BasicBlock, block, *loopBlocks) {
        for_vector(BasicBlock, out, block->outs) {
          if(bitBlocks->test(out->id) == false) {
            bitExits->set(block->id);
          }
        }
      }
      return bitExits;
    }
    
    //return the number of blocks in the loop
    unsigned size() {
      return loopBlocks->size();
    }

    //used for sorting a collection of loops (to organize from most to least nested)
     static bool LoopSort(Loop* a, Loop* b) {return a->size() < b->size();}

};

typedef std::vector<BasicBlock*> BasicBlocks;
typedef std::map<Symbol*,std::vector<SymExpr*>*> symToVecSymExprMap;

//These two functions are used to collect all natural loops from a bunch of basic blocks and ensure the loops are stored 
//from most nested to least nested for any give loop nest 
void collectNaturalLoops(std::vector<Loop*>& loops, BasicBlocks& basicBlocks, BasicBlock* entryBlock, std::vector<BitVec*>& dominators);
void collectNaturalLoopForEdge(Loop* loop, BasicBlock* header, BasicBlock* tail);


/*
 * This function identifies all of the natural loops from a collection of basic blocks 
 * using the dominators of each block. The basic idea is that for each basic block 
 * look at the basic blocks that it can go to. If block(1)'s successor is block(2)  
 * and block(2) dominates block(1) then we know that block(1) is a back-edge and that
 * block(2) is the header of a natural loop. 
 * 
 * From there we check if the loop header is already part of another loop (shared header)
 * which should be infrequent in chapel generated code. We treat loops with shared headers 
 * as a single loop. The last step is to sort the list of loops from the loops with smallest
 * number of blocks to the largest. This has the effect of organizing the loops from most to 
 * least nested for any given loop nest. 
 *
 * The end result is that you have a list of all the natural loops that appeared in the basic 
 * blocks and that they are sorted from most nested to least nested in the sense that for any 
 * given nested loop structure the most nested one is guaranteed to appear before (closer to 
 * index 0) than the more outer loops.)
 */
void collectNaturalLoops(std::vector<Loop*>& loops, BasicBlocks& basicBlocks, BasicBlock* entryBlock, std::vector<BitVec*>& dominators) {

  for_vector(BasicBlock, block, basicBlocks) {
    //Skip entry blocks
    if(block == entryBlock || block->exprs.size() == 0){
      continue;
    }
    
    //for each successor 
    for_vector(BasicBlock, successor, block->outs) {
      //if the successor dominates the block, block is a back-edge and successor is a header 
      if(dominates(successor->id, block->id, dominators)) {
        //check if this loop shares a header with any previous one, and if so combine them into one
        bool sharedHeader = false;
        for_vector(Loop, loop, loops) {
          //if this loop shares a header with an existing one, add this loop to the existing one
          if(loop->getHeader() == successor) {
            sharedHeader = true;
            collectNaturalLoopForEdge(loop, successor, block);
          }
        } 
        //if the headers weren't shared, create a new loop
        if(sharedHeader == false) {      
          Loop* loop = new Loop(basicBlocks.size());
          collectNaturalLoopForEdge(loop, successor, block);
          loops.push_back(loop);
        }
      }
    }
  }
  //sort by most nested, to least nested for any given loop nest
  std::sort(loops.begin(), loops.end(), Loop::LoopSort);
}
 
 
/*
 * This function collects the blocks in a natural loop that goes from the header to the 
 * tail (back edge) and stores all of the blocks that are in the loop in an initially 
 * empty loop. 
 *
 * Starting from the tail of the loop, work your way backwards and iteratively collect 
 * all of the predecessors until you reach the head of the loop
 */
void collectNaturalLoopForEdge(Loop* loop, BasicBlock* header, BasicBlock* tail) {

  std::stack<BasicBlock*> workList; 
  loop->setHeader(header);

  //If we don't have a one block loop, add the tail 
  //to the worklist and start finding predecessors from there
  if(header != tail) {
   loop->insertBlock(tail);
   workList.push(tail);
  }

  //While we have more blocks to look at 
  while(workList.empty() == false) {
    BasicBlock* block = workList.top();
    workList.pop();
    //look at all the predecessors so long as they are not already added
    for_vector(BasicBlock, in, block->ins) {
      if(loop->contains(in) == false) { 
        loop->insertBlock(in);
        workList.push(in);
      }
    }
  } 
}


// Returns rhs var if lhs aliases rhs
//
//
static Symbol*
rhsAlias(CallExpr* call) {
  if (call->isPrimitive(PRIM_MOVE) ||
      call->isPrimitive(PRIM_SET_MEMBER) ||
      call->isPrimitive(PRIM_SET_SVEC_MEMBER)) {
    SymExpr* lhs;
    Expr *rhsT;
    if (call->isPrimitive(PRIM_MOVE)) {
      lhs = toSymExpr(call->get(1));
      rhsT = call->get(2);
    } else {
      lhs = toSymExpr(call->get(2));
      rhsT = call->get(3);
    }
    INT_ASSERT(lhs);
    if (SymExpr* rhs = toSymExpr(rhsT)) {
      // direct alias
      return rhs->var;
    } else if (CallExpr* rhsCall = toCallExpr(rhsT)) {
      if (rhsCall->primitive) {
        if (rhsCall->isPrimitive(PRIM_GET_MEMBER_VALUE) ||
            rhsCall->isPrimitive(PRIM_GET_MEMBER) ||
            rhsCall->isPrimitive(PRIM_GET_SVEC_MEMBER_VALUE) ||
            rhsCall->isPrimitive(PRIM_GET_SVEC_MEMBER)) {
          SymExpr* rhs = toSymExpr(rhsCall->get(2));
          INT_ASSERT(rhs);
          return rhs->var;
        } else if(rhsCall->isPrimitive(PRIM_ADDR_OF)) {
          SymExpr* rhs = toSymExpr(rhsCall->get(1));
          INT_ASSERT(rhs);
          return rhs->var;
        }
      } else {
        // alias via autocopy
        SymExpr* fnExpr = toSymExpr(rhsCall->baseExpr);
        INT_ASSERT(fnExpr);
        if (fnExpr->var->hasFlag(FLAG_AUTO_COPY_FN)) {
          SymExpr* rhs = toSymExpr(rhsCall->get(1));
          INT_ASSERT(rhs);
          return rhs->var;
        }
      }
    }
  }
  return NULL;
}


/*
 * Some primitives will not produce loop invariant results. 
 * this is the list of ones that will
 */
static bool isLoopInvariantPrimitive(PrimitiveOp* primitiveOp)
{
  switch (primitiveOp->tag)
  {
      case PRIM_MOVE:
      case PRIM_UNARY_MINUS:
      case PRIM_UNARY_PLUS:
      case PRIM_UNARY_NOT:
      case PRIM_UNARY_LNOT:
      case PRIM_ADD:
      case PRIM_SUBTRACT:
      case PRIM_MULT:
      case PRIM_DIV:
      case PRIM_MOD:
      case PRIM_LSH:
      case PRIM_RSH:
      case PRIM_EQUAL:
      case PRIM_NOTEQUAL:
      case PRIM_LESSOREQUAL:
      case PRIM_GREATEROREQUAL:
      case PRIM_LESS:
      case PRIM_GREATER:
      case PRIM_AND:
      case PRIM_OR:
      case PRIM_XOR:
      case PRIM_POW:
    
      case PRIM_ADD_ASSIGN:
      case PRIM_SUBTRACT_ASSIGN:
      case PRIM_MULT_ASSIGN:
      case PRIM_DIV_ASSIGN:
      case PRIM_MOD_ASSIGN:
      case PRIM_LSH_ASSIGN:
      case PRIM_RSH_ASSIGN:
      case PRIM_AND_ASSIGN:
      case PRIM_OR_ASSIGN:
      case PRIM_XOR_ASSIGN:

      case PRIM_MIN:
      case PRIM_MAX:
    
      case PRIM_SETCID:
      case PRIM_TESTCID:
      case PRIM_GETCID:
      case PRIM_SET_UNION_ID:
      case PRIM_GET_UNION_ID:
      case PRIM_GET_MEMBER:
      case PRIM_GET_MEMBER_VALUE:
      case PRIM_SET_MEMBER:
      case PRIM_CHECK_NIL:
      case PRIM_GET_REAL:            
      case PRIM_GET_IMAG:   
      
      case PRIM_SET_SVEC_MEMBER:
      case PRIM_GET_SVEC_MEMBER:
      case PRIM_GET_SVEC_MEMBER_VALUE:        
    
      case PRIM_ADDR_OF:            
      case PRIM_DEREF:    
        return true;
    default:
      break;
    }
  
  // otherwise
  return false;
}


/*
 * Simple function to check if a symExpr is constant 
 */
static bool isConst(SymExpr* symExpr) {
  if(VarSymbol* varSymbol = toVarSymbol(symExpr->var)) {
    if(varSymbol->immediate) {
      return true;
    }
  }
  return false;
  
  //TODO can we use vass's backend const?
  //check if its chapel const?
  //check for other things that can make it const?
}


/*
 * TODO The following three functions duplicate most of the functionality that is in the 
 * routines found in astUtil. However, these use the STL containers instead of the 
 * old map and vec. Additionally the astUtil implementation is wrong for the primitive
 * set member (its not identified as a def -- there is a similar note in iterator.cpp.)
 * This is a shunt until the astutil can be updated to use STL and is corrected. After 
 * that these three functions can be replaced by one that just uses the buildDefUseMaps 
 * that takes the set of symbols and symExpr to look in
 */


/*
 * Small helper method for adding a def/use so clean up the code for doing so a bit
 */
static void addDefOrUse(symToVecSymExprMap& localDefOrUseMap, SymExpr* defOrUse) {
  if(localDefOrUseMap[defOrUse->var] == NULL) {
    localDefOrUseMap[defOrUse->var] = new std::vector<SymExpr*>;
  }
  localDefOrUseMap[defOrUse->var]->push_back(defOrUse);
}


/*
 * Build the local def use maps for a loop and while we're at it built the local map which is the map from each 
 * symExpr to the block it it is defined in.
 */
static void buildLocalDefUseMaps(Loop* loop, symToVecSymExprMap& localDefMap, symToVecSymExprMap& localUseMap, std::map<SymExpr*, int>& localMap) {

  for_vector(BasicBlock, block, *loop->getBlocks()) {
    for_vector(Expr, expr, block->exprs) {
      //check if the current expr is a set member call and add the symExpr if it is 
      if(CallExpr* callExpr = toCallExpr(expr)) {
        if(callExpr->isPrimitive(PRIM_SET_MEMBER)) {
          if(SymExpr* symExpr = toSymExpr(callExpr->get(2))) {
            addDefOrUse(localDefMap, symExpr);
          }
        } else if(callExpr->isPrimitive(PRIM_SET_SVEC_MEMBER)) {
          if(SymExpr* symExpr = toSymExpr(callExpr->get(1))) {
            addDefOrUse(localDefMap, symExpr);
          }
        }
      }
    
      //Check each symExpr to see if its a use and or def and add to the appropriate lists
      std::vector<SymExpr*> symExprs;
      collectSymExprsSTL(expr, symExprs);
      for_vector(SymExpr, symExpr, symExprs) {
        if(symExpr->parentSymbol) {
          if(isVarSymbol(symExpr->var) || isArgSymbol(symExpr->var)) {
            localMap[symExpr] = block->id;
            int result = isDefAndOrUse(symExpr);
            if(result & 1) {
              addDefOrUse(localDefMap, symExpr);
            }
            if(result & 2) {
              if(CallExpr* callExpr = toCallExpr(symExpr->parentExpr)) {
                if(callExpr->isResolved()) {
                  addDefOrUse(localDefMap, symExpr);
                }
              }
              addDefOrUse(localUseMap, symExpr);
            }
          }
        }
      }
    }
  }   
}


/*
 * Free the def and use maps 
 */
static void freeLocalDefUseMaps(symToVecSymExprMap& localDefMap, symToVecSymExprMap& localUseMap) {
 symToVecSymExprMap::iterator it;
  for(it = localDefMap.begin(); it != localDefMap.end(); it++) {
    delete it->second;
  }
  for(it = localUseMap.begin(); it != localUseMap.end(); it++) {
    delete it->second;
  }
}

 
/* 
 * Determines if the expr is loop invariant, based on the current 
 * list of loop invariants
 *
 * This should only be called externally on a call expr whose lhs has only one def in a loop
 */
static bool allOperandsAreLoopInvariant(Expr* expr, std::set<SymExpr*>& loopInvariants, std::set<SymExpr*>& loopInvariantInstructions, Loop* loop,   std::map<SymExpr*, std::set<SymExpr*> >& actualDefs) {

  //if we have an assignment, recursively compute if all operands are invariant
  //if there was a different loop invariant operand, make sure all its arguments 
  //are invariant
  if(CallExpr* callExpr = toCallExpr(expr)) {
    if(callExpr->primitive && isLoopInvariantPrimitive(callExpr->primitive)) {
      if(callExpr->isPrimitive(PRIM_MOVE)) {  
        return allOperandsAreLoopInvariant(callExpr->get(2), loopInvariants, loopInvariantInstructions, loop, actualDefs);
      }  
      else {
        for_alist(arg, callExpr->argList) {
          if(allOperandsAreLoopInvariant(arg, loopInvariants, loopInvariantInstructions, loop, actualDefs) == false) {
            return false;
          }
        }
        return true;
      }
    }
    return false;
  } else if(SymExpr* symExpr = toSymExpr(expr)) {
  
    //do not hoist things that are wide 
    bool isWideObj = symExpr->var->type->symbol->hasFlag(FLAG_WIDE_CLASS);
    bool isWideRef = symExpr->var->type->symbol->hasFlag(FLAG_WIDE);
    bool isWideStr = isWideString(symExpr->var->type);
    if(isWideObj || isWideRef || isWideStr) {
      return false;
    }
  
    //If the operand is invariant (0 defs in the loop, or constant)
    //it is invariant 
    if(loopInvariants.count(symExpr) == 1) {
      return true;
    }
    
    //else check if there is only one def for the symExpr. That the 
    //def is invariant, and that the def occurs before this symExpr
    int numDefs = 0;
    SymExpr* def = NULL;
    
    if(actualDefs.count(symExpr) == 1) {
      numDefs += actualDefs[symExpr].size();
      if(actualDefs[symExpr].size() == 1) {
        def = *actualDefs[symExpr].begin();
      }
    }
    
    if(numDefs > 1 || def == NULL) {
      return false;
    }
    
    //if the def is loop invariant 
    if(loopInvariantInstructions.count(def) == 1)  {
      //if the def comes from a call, we can't guarantee 
      //its invariant without more analysis
      if(CallExpr* call = toCallExpr(def->parentExpr)) {
        if (call->isResolved()) {
          return false;
        }
      }       
      
      //check that the def occurs before this symExpr
      bool sawDef = false;
      for_vector(BasicBlock, block, *loop->getBlocks()) {
        for_vector(Expr, expr, block->exprs) {
          std::vector<SymExpr*> symExprs;
          collectSymExprsSTL(expr, symExprs);
          for_vector(SymExpr, symExpr2, symExprs) {

            //mark that we have seen the definition of the operand 
            if(def == symExpr2) {
              sawDef = true;
            }
             //if we saw a use of the var before its def, not invariant
            if(symExpr2->var == def->var) { 
              if(sawDef == false)
                return false;
            }
            //if we have seen our symExpr that uses the def after the actual def,we're good
            if(symExpr == symExpr2) {
              if(sawDef == true) {
                  return true;
              }
            }
          }
        }
      }
    }
    return false;  
  }
  return false;
}


/*
 * The basic algorithm will be to find all of the constants, and then find things that 
 * have no definitions in the loop. We also need to consider a symbols aliases when we're 
 * talking about if it has any definitions. So if symbol and all its aliases have no definitions
 * then it is loop invariant. We need to think carefully about this because the alias will definitely 
 * have one definition and that is where it is assigned to whatever it is aliasing. So if we have a = &b
 * Then a is an alias for b. The current alias analysis is extremely conservative. If there is only one def
 * of a variable check if it is composed of loop invariant operands and operations. 
 */
static void computeLoopInvariants(std::vector<SymExpr*>& loopInvariants, Loop* loop, symToVecSymExprMap& localDefMap) {
 
  //collect all of the symExpr and defExpr in the loop 
  startTimer(collectSymExprAndDefTimer);
  std::vector<SymExpr*> loopSymExprs;
  std::set<Symbol*> defsInLoop;
  for_vector(BasicBlock, block, *loop->getBlocks()) {
    for_vector(Expr, expr, block->exprs) {
      collectSymExprsSTL(expr, loopSymExprs);
      if (DefExpr* defExpr = toDefExpr(expr)) {
        if (toVarSymbol(defExpr->sym)) {
          defsInLoop.insert(defExpr->sym);
        }
      }
    }
  }
  stopTimer(collectSymExprAndDefTimer);
  
  //compute the map of aliases for each symbol 
  startTimer(computeAliasTimer);
  std::map<Symbol*, std::set<Symbol*> > aliases;
  for_vector(BasicBlock, block2, *loop->getBlocks()) {
    for_vector(Expr, expr, block2->exprs) {
      if(CallExpr* call = toCallExpr(expr)) {
        Symbol* alias  = rhsAlias(call);
        if(alias != NULL) {
          SymExpr* symExpr = toSymExpr(call->get(1));
          aliases[alias].insert(symExpr->var);
          for_set(Symbol, symbol, aliases[alias]) {
            aliases[symbol].insert(symExpr->var);
          }
          aliases[symExpr->var].insert(alias);
         // for_set(Symbol, symbol2, aliases[symExpr->var]) {
         //   aliases[symbol2].insert(symExpr->var);
         // } 
        }
      }
    }
  }
  stopTimer(computeAliasTimer);
  
  //calculate the actual defs of a symbol including the defs of 
  //its aliases. If there are no defs or we have a constant, 
  //add it to the list of invariants
  startTimer(calculateActualDefsTimer);
  std::set<SymExpr*> loopInvariantOperands;  
  std::set<SymExpr*> loopInvariantInstructions;
  std::map<SymExpr*, std::set<SymExpr*> > actualDefs;
  for_vector(SymExpr, symExpr, loopSymExprs) {
  
    //skip already known invariants
    if(loopInvariantOperands.count(symExpr) == 1) {
      continue;
    }
    
    //mark all the const operands 
    if(isConst(symExpr)) {
      loopInvariantOperands.insert(symExpr);
    }    
        
    //calculate defs of the aliases
    if(aliases.count(symExpr->var) == 1) {
      for_set(Symbol, symbol, aliases[symExpr->var]) {
        if(localDefMap.count(symbol) == 1) {
          //for each symExpr that defines the alias
          for_vector(SymExpr, aliasSymExpr, *localDefMap[symbol]) {
            if(CallExpr* call = toCallExpr(aliasSymExpr->parentExpr)) {
              if(symExpr->var == rhsAlias(call)) {
                //do nothing 
              }
              else if(aliases[symExpr->var].count(rhsAlias(call)) == 0) {
                actualDefs[symExpr].insert(aliasSymExpr);
              }  
            }
          }
        }
      }
    }    
    
    //add the defs of the symbol itself
    if(localDefMap.count(symExpr->var) == 1) {
      for_vector(SymExpr, aliasSymExpr, *localDefMap[symExpr->var]) {
        actualDefs[symExpr].insert(aliasSymExpr);
      }
    }
    
    //if there were no defs of the symbol, it is invariant 
    if(actualDefs.count(symExpr) == 0) {
      loopInvariantOperands.insert(symExpr);
    }
  }
  stopTimer(calculateActualDefsTimer);
  
  //now we want to iteratively search for all of the variables that have 
  //operands that themselves are loop invariant. 
  unsigned oldNumInvariants = 0;
  do {
    oldNumInvariants = loopInvariantInstructions.size();  

    for_vector(SymExpr, symExpr2, loopSymExprs) {

      if(loopInvariantInstructions.count(symExpr2) == 1 || loopInvariantOperands.count(symExpr2) == 1) {
        continue;
      }
      //if there is only one def of that variable check if it is loop invariant too 
      //Also check that the definition of the variable is inside the loop. This ensures 
      //that the variable is not live into the loop
      if(actualDefs.count(symExpr2) == 1) {
        if(actualDefs[symExpr2].size() == 1) {
          if(defsInLoop.count(symExpr2->var) == 1) {
            if(CallExpr* callExpr = toCallExpr(symExpr2->parentExpr)) {
              if(callExpr->isPrimitive(PRIM_MOVE)) {
                startTimer(allOperandsAreLoopInvariantTimer);   
                bool loopInvarOps = allOperandsAreLoopInvariant(callExpr, loopInvariantOperands, loopInvariantInstructions, loop, actualDefs);
                stopTimer(allOperandsAreLoopInvariantTimer);
                if(loopInvarOps){
                  loopInvariantInstructions.insert(symExpr2);
                  loopInvariants.push_back(symExpr2);
                }
              } 
            }
          }
        }
      }
    }
  }  while(oldNumInvariants != loopInvariantInstructions.size());
  
 
#if debugHoisting
  printf("\n");
  printf("HOISTABLE InvariantS\n");
  for_vector(SymExpr, loopInvariant, loopInvariants) {
    printf("Symbol %s with id %d is a hoistable loop invariant\n", loopInvariant->var->name, loopInvariant->var->id);
  }
  
  printf("\n\n\n");
  printf("Invariant OPERANDS\n");
  for_set(SymExpr, symExpr2, loopInvariantOperands) {
    printf("%s %d is invariant\n", symExpr2->var->name, symExpr2->id);
  }
  
  printf("\n\n\n");
  for_vector(SymExpr, symExpr3, loopSymExprs) {
    printf("%s is used/ defed\n", symExpr3->var->name);
  } 
#endif  
 
}


/*
 * In order to be hoisted a definition of a variable needs to dominate all uses. 
 *
 * Consider a case where you have 
 * if(first)
 *   first = false;
 *
 * Even though first = false is loop invariant, you clearly don't want to hoist it 
 * because that would have the effect of executing first = false before the use. 
 *
 */
static bool defDominatesAllUses(Loop* loop, SymExpr* def, std::vector<BitVec*>& dominators, std::map<SymExpr*, int>& localMap, symToVecSymExprMap& localUseMap) {
  
  if(localUseMap.count(def->var) == 0 ) {
    return false;
  }
  
  int defBlock = localMap[def];
  
  for_vector(SymExpr, symExpr, *localUseMap[def->var]) {
    if(dominates(defBlock, localMap[symExpr], dominators) == false) {
      return false;
    }
  }
  return true;
}


/*
 * Check if a definition dominates all the loop exits. The loop exits can be gotten from the loop, and beyond that we 
 * need the dominators and the map from SymExpr to the block they are used/defed in 
 *
 * Consider a case where you have a live out variable from the loop:
 * if(cond1) 
 *   goto exitLoop;
 * if (cond2)
 *   b = 4;
 *
 * exitLoop: 
 *   writeln(b);
 *
 * b's definition is loop invariant, but you have to ensure that the def will dominate the exit blocks 
 * where it may be used. 
 *
 */
static bool defDominatesAllExits(Loop* loop, SymExpr* def, std::vector<BitVec*>& dominators, std::map<SymExpr*, int>& localMap) {
  int defBlock = localMap[def];
  
  BitVec* bitExits = loop->getBitExits();
   
  for(int i = 0; i < bitExits->size(); i++) {
    if(bitExits->test(i)) {
      if(dominates(defBlock, i, dominators) == false) {
        return false;
      }
    }
  }
  return true;
}


/*
 * Collect all of the function symbols that belong to function calls 
 * and nested function calls that occur from baseAST. In other words
 * look through the baseAST and find all the function and nested function
 * calls and collect their fnsymbols. 
 */
static void collectUsedFnSymbolsSTL(BaseAST* ast, std::set<FnSymbol*>& fnSymbols) {
  AST_CHILDREN_CALL(ast, collectUsedFnSymbolsSTL, fnSymbols);
  //if there is a function call, get the FnSymbol associated with it 
  //and look through that FnSymbol for other function calls. Do not 
  //look through an already visited FnSymbol, or you'll have an infinite
  //loop in the case of recursion. 
  if (CallExpr* call = toCallExpr(ast)) {
    if (FnSymbol* fnSymbol = call->isResolved()) {
      if(fnSymbols.count(fnSymbol) == 0) {
        fnSymbols.insert(fnSymbol);
        for_alist(expr, fnSymbol->body->body) {
          AST_CHILDREN_CALL(expr, collectUsedFnSymbolsSTL, fnSymbols);
        }
      }
    }
  }
}


/*
 * Collects the uses and defs of symbols the baseAST 
 * and checks for any synchronization variables such as 
 * atomics, syncs, and singles. 
 */
static bool containsSynchronizationVar(BaseAST* ast) {
  std::vector<SymExpr*> symExprs;
  collectSymExprsSTL(ast, symExprs);
  for_vector(SymExpr, symExpr, symExprs) {
    
    if(isVarSymbol(symExpr->var) || isArgSymbol(symExpr->var)) {
      bool isSync = symExpr->var->type->symbol->hasFlag(FLAG_SYNC);
      bool isSingle = symExpr->var->type->symbol->hasFlag(FLAG_SINGLE);
      bool isAtomic = symExpr->var->type->symbol->hasFlag(FLAG_ATOMIC_TYPE);

      if(isSync || isSingle || isAtomic) {
        return true;
      }
    }  
  }
  return false;
}


// TODO Looking for synchronization variables is very 
// similar to what is currently being done in remote
// value forwarding. It would be a good idea to unify
// the two implementations. 

/*
 * Checks if a loop can have loop invariant code motion 
 * performed on it. Specifically we do not want to hoist
 * from loops that have sync, single, or atomic vars in 
 * them, though there may be others in the future. Also, 
 * Do not perform code motion if any function calls or
 * nested function calls contains syncs, atomics, or 
 * singles. 
 */
static bool canPerformCodeMotion(Loop* loop) {
  
  for_vector(BasicBlock, block, *loop->getBlocks()) {
    for_vector(Expr, expr, block->exprs) {
  
      //Check for nested function calls containing 
      //synchronization variables 
      std::set<FnSymbol*> fnSymbols;
      collectUsedFnSymbolsSTL(expr, fnSymbols);
      for_set(FnSymbol, fnSymbol2, fnSymbols) {
        if(containsSynchronizationVar(fnSymbol2)) {
          return false;
        }
      }
    
      //Check if there are any synchronization variables
      //in the current expr 
      if(containsSynchronizationVar(expr)) {
        return false;
      } 
    }
  }
  return true;
}


/*
 * The basic algorithm for loop invariant code motion is as follows:
 * First figure out where the loops actually are. To do this the dominators need 
 * to be computed and then the natural loops can be collected.
 *
 * Now that you have identified the loops you can compute the invariants. A definition
 * is invariant if the operations are loop and invariant and all the operands are loop 
 * invariant. An operand is loop invariant if it is constant, has no definitions that 
 * reach it located inside of the loop, or it has one definition that reaches it, that
 * definition is in the loop, and that definition is itself loop invariant. 
 *
 * You now have a list of all the definitions that are loop invariant, these can be 
 * hoisted before the loop(into a preheader of sorts) so long as they definition dominates
 * all uses in the loop, and the block that the definition is located in dominates all exits. 
 */
void loopInvariantCodeMotion(void) {

  if(fNoloopInvariantCodeMotion) {
    return;
  }
  
  startTimer(overallTimer);
  long numLoops = 0;
    
  //TODO use stl routine here
  forv_Vec(FnSymbol, fn, gFnSymbols) {
  
    //build the basic blocks, where the first bb is the entry block 
    startTimer(buildBBTimer);
    buildBasicBlocks(fn);
    std::vector<BasicBlock*> basicBlocks = *fn->basicBlocks;
    BasicBlock* entryBlock = basicBlocks[0];
    unsigned nBlocks = basicBlocks.size();
    stopTimer(buildBBTimer);
    
    //compute the dominators 
    startTimer(computeDominatorTimer);
    std::vector<BitVec*> dominators;
    for(unsigned i = 0; i < nBlocks; i++) {
      dominators.push_back(new BitVec(nBlocks));
    }    
    computeDominators(dominators, basicBlocks);
    stopTimer(computeDominatorTimer);

    //Collect all of the loops 
    startTimer(collectNaturalLoopsTimer);
    std::vector<Loop*> loops;
    collectNaturalLoops(loops, basicBlocks, entryBlock, dominators);
    stopTimer(collectNaturalLoopsTimer);

    //For each loop found 
    for_vector(Loop, curLoop, loops) {
      
      //check that this loop doesn't have anything that 
      //would prevent code motion from occurring
      startTimer(canPerformCodeMotionTimer);
      bool performCodeMotion = canPerformCodeMotion(curLoop);
      stopTimer(canPerformCodeMotionTimer);
      if(performCodeMotion == false) {
        continue;
      }
      
      //build the defUseMaps 
      startTimer(buildLocalDefMapsTimer);
      symToVecSymExprMap localDefMap;
      symToVecSymExprMap localUseMap;
      std::map<SymExpr*, int> localMap;
      buildLocalDefUseMaps(curLoop, localDefMap, localUseMap, localMap);
      stopTimer(buildLocalDefMapsTimer);

      //and use the defUseMaps to compute loop invariants 
      startTimer(computeLoopInvariantsTimer);
      std::vector<SymExpr*> loopInvariants;
      computeLoopInvariants(loopInvariants, curLoop, localDefMap);
      stopTimer(computeLoopInvariantsTimer);

      //For each invariant, only move it if its def, dominates all uses and all exits 
      for_vector(SymExpr, symExpr, loopInvariants) {
        if(CallExpr* call = toCallExpr(symExpr->parentExpr)) {
          if(defDominatesAllUses(curLoop, symExpr, dominators, localMap, localUseMap)) {
            if(defDominatesAllExits(curLoop, symExpr, dominators, localMap)) {
              curLoop->insertBefore(call);
            }
          }   
        }
      }
                
      freeLocalDefUseMaps(localDefMap, localUseMap);
      numLoops+= loops.size();
    }
   
    for_vector(Loop, loop, loops) {
      delete loop;
      loop = 0;
    }
    
    for_vector(BitVec, bitVec, dominators) {
      delete bitVec;
      bitVec = 0;
    }
  }

  stopTimer(overallTimer);
    
#ifdef detailedTiming  
  FILE *timingFile;
  FILE *maxTimeFile;
  timingFile = stdout;
  maxTimeFile = stdout;
  //timingFile = fopen("/data/cf/gtmp/chapel/eronagha/timing.txt", "a");    //TODO Where's an appropriate location?
  //maxTimeFile = fopen("/data/cf/gtmp/chapel/eronagha/maxTime.txt", "a");

  fprintf(timingFile, "For compilation of %s:                         \n", compileCommand );
  fprintf(timingFile, "Spent %2.3f seconds building basic blocks      \n", buildBBTimer.elapsed()); 
  fprintf(timingFile, "Spent %2.3f seconds computing dominators       \n", computeDominatorTimer.elapsed()); 
  fprintf(timingFile, "Spent %2.3f seconds collecting natural loops   \n", collectNaturalLoopsTimer.elapsed()); 
  fprintf(timingFile, "Spent %2.3f seconds building local def maps    \n", buildLocalDefMapsTimer.elapsed()); 
  fprintf(timingFile, "Spent %2.3f seconds on can perform code motion \n", canPerformCodeMotionTimer.elapsed());
  fprintf(timingFile, "Spent %2.3f seconds computing loop invariants  \n", computeLoopInvariantsTimer.elapsed()); 
   
  double estimateOverall = buildBBTimer.elapsed() + computeDominatorTimer.elapsed() + collectNaturalLoopsTimer.elapsed() + \
  buildLocalDefMapsTimer.elapsed() + canPerformCodeMotionTimer.elapsed() + computeLoopInvariantsTimer.elapsed();
  
  
  fprintf(timingFile, "Spent %2.3f seconds loop hoisting on %ld loops \n", overallTimer.elapsed(), numLoops);
  fprintf(timingFile, "      %2.3f seconds unaccounted for            \n", overallTimer.elapsed() - estimateOverall);
  
  double estimateInvariant = allOperandsAreLoopInvariantTimer.elapsed() + computeAliasTimer.elapsed() + \
  collectSymExprAndDefTimer.elapsed() + calculateActualDefsTimer.elapsed();
  
  fprintf(timingFile, "\n");
  fprintf(timingFile, "In loop invariant computation:                 \n");
  fprintf(timingFile, "Spent %2.3f seconds collecting sym/def Expr    \n", collectSymExprAndDefTimer.elapsed());
  fprintf(timingFile, "Spent %2.3f seconds computing aliases          \n", computeAliasTimer.elapsed());
  fprintf(timingFile, "Spent %2.3f seconds calculating actual defs    \n", calculateActualDefsTimer.elapsed());
  fprintf(timingFile, "Spent %2.3f seconds in allOperandsAreInvariant \n", allOperandsAreLoopInvariantTimer.elapsed());

  fprintf(timingFile, "      %2.3f seconds unaccounted for            \n\n", computeLoopInvariantsTimer.elapsed() - estimateInvariant);
  fprintf(timingFile, "_______________________________________________\n\n\n");
  
  
  fprintf(maxTimeFile, "For compilation of %s:                         \n", compileCommand );
  fprintf(maxTimeFile, "Spent %2.3f seconds loop hoisting on %ld loops \n\n", overallTimer.elapsed(), numLoops);
  fprintf(maxTimeFile, "_______________________________________________\n\n\n");
  
  fclose(timingFile);
  fclose(maxTimeFile);
#endif

}
