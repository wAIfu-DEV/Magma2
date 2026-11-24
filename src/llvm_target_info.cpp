#include <llvm/TargetParser/Host.h>

#include <iostream>

int main() {
  std::cout << llvm::sys::getDefaultTargetTriple() << '\n';
  return 0;
}
