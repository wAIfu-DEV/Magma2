// Used for compile-time retrieval of the target triple of the system
// @author codex (GPT6 Luna)

#include <llvm/TargetParser/Host.h>

#include <iostream>

int main() {
  std::cout << llvm::sys::getDefaultTargetTriple() << '\n';
  return 0;
}
