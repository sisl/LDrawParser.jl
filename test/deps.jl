# A script for loading unregistered dependencies before CI action
using Pkg

pkg"add https://github.com/sisl/GraphUtils.jl.git"
