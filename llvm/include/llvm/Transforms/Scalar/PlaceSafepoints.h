//===- PlaceSafepoints.h - ------------------------------*- C++ -*-===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// This file provides interface to "PlaceSafepoints" pass.
//
// Place garbage collection safepoints at appropriate locations in the IR. This
// does not make relocation semantics or variable liveness explicit.  That's
// done by RewriteStatepointsForGC.
//
//===----------------------------------------------------------------------===//

#ifndef LLVM_TRANSFORMS_SCALAR_PLACE_SAFEPOINTS_H
#define LLVM_TRANSFORMS_SCALAR_PLACE_SAFEPOINTS_H

#include "llvm/IR/PassManager.h"

namespace llvm {

class DominatorTree;
class Function;
class Instruction;
class TargetLibraryInfo;

struct PlaceSafepoints : public PassInfoMixin<PlaceSafepoints> {
  PreservedAnalyses run(Function &F, FunctionAnalysisManager &FAM);

  bool runOnFunction(Function &F, DominatorTree &DT, const TargetLibraryInfo &, std::vector<Instruction *> &);
};

} // namespace llvm

#endif // LLVM_TRANSFORMS_SCALAR_PLACE_SAFEPOINTS_H
