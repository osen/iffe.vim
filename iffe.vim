#!/usr/local/bin/vim -S

" BSD / LLVM
let s:compiler = "clang++"
let s:objSuffix = "o"
let s:exeSuffix = ""

" DOS / DJGPP
"let s:compiler = "g++"
"let s:objSuffix = "o"
"let s:exeSuffix = "exe"

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" Output
"
" Write the specified message to the buffer using normal mode and then request
" a redraw to ensure that the text is visible even if further processing is
" needing to be done.
"
" message - The message to add to the buffer
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
function Output(message)

  execute("normal! Ga" . a:message . "\n")
  redraw!

endfunction

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" FileCreate
"
" Based on the specified path, populate a structure for the relevent file.
" The data to be populated includes information on whether it is a header or
" source unit. If a source unit, then generate a path to be used for the
" compiled object. If the file is called "main" then set the executable flag
" in the parent project so it is known to not just be a library.
"
" project - The parent project of this file
" path - The relative file path
"
" Returns - The populated file structure
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
function FileCreate(project, path)

  let l:ctx = {}
  let l:ctx.project = a:project
  let l:ctx.path = a:path
  let l:ctx.name = fnamemodify(l:ctx.path, ':t')
  let l:ctx.absolutepath = fnamemodify(l:ctx.path, ':p')
  let l:ctx.timestamp = getftime(l:ctx.path)
  let l:ctx.dependencies = []

  if fnamemodify(l:ctx.path, ':e') == "cpp"
    let l:ctx.objpath = fnamemodify(l:ctx.path, ':t:r')

    if l:ctx.objpath == "main"
      let a:project.executable = 1
    endif

    let l:objpath = "obj/" . l:ctx.project.name . "/"
    let l:objpath = l:objpath . l:ctx.objpath . "." . s:objSuffix
    let l:ctx.objpath = l:objpath
  else
    let l:ctx.objpath = ""
  endif

  return l:ctx

endfunction

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" DepParserCreate
"
" Create a structure containing the necessary data store for the dependency
" parser. In particular create two arrays referring to the open and closed
" list and prepopulate the open list with the initial source unit to scan.
"
" file - The file to pre-populate the open list with
"
" Returns - The created parser context
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
function DepParserCreate(file)

  let ctx = {}
  let ctx.iffe = a:file.project.iffe
  let ctx.open = []
  call add(ctx.open, a:file)
  let ctx.closed = []

  return ctx

endfunction

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" DepParserProcess
"
" Read the required files and generate a list of all included dependencies
" recursively. The method itself is not recursive (to reduce the required
" stack size on weaker platforms such as DOS) and as such uses an open / closed
" list system (in a similar way to path finding). By the end of the process the
" closed list within the context will contain the initial files and all of
" their dependencies.
"
" ctx - The parser context
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
function DepParserProcess(ctx)

  while len(a:ctx.open) > 0
    let l:file = a:ctx.open[0]
    call remove(a:ctx.open, 0)
    call add(a:ctx.closed, l:file)

    let l:data = readfile(l:file.path)

    for l:line in l:data
      if l:line =~ "^#include"
        let l:line = substitute(l:line, '"\s*$', "", "")
        let l:line = substitute(l:line, '>\s*$', "", "")
        let l:line = substitute(l:line, '^.*"', "", "")
        let l:line = substitute(l:line, '^.*<', "", "")

        let l:inc = fnamemodify(l:line, ':t')
        let l:found = 0

        for l:ent in a:ctx.open
          if l:ent.name == l:inc
            let l:found = 1
            break
          endif
        endfor

        if l:found == 0
          for l:ent in a:ctx.closed
            if l:ent.name == l:inc
              let l:found = 1
              break
            endif
          endfor
        endif

        if l:found == 0
          for l:ent in a:ctx.iffe.headers
            if l:ent.name == l:inc
              call add(a:ctx.open, l:ent)
            endif
          endfor
        endif
      endif
    endfor

  endwhile

endfunction

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" SourceUpdateDependencies
"
" Update all the dependencies of the specified source file by creating an
" instance of the file parser, adding any source file with the specified file's
" name, and processing it. All files in the closed list which are header files
" are copied into the source as dependencies (replacing the existing list).
"
" ctx - The source file to update
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
function SourceUpdateDependencies(ctx)

  let l:dp = DepParserCreate(a:ctx)

  for l:src in a:ctx.project.iffe.sources
    if l:src == a:ctx
      continue
    endif

    if l:src.name == a:ctx.name
      call add(l:dp.open, l:src)
    endif
  endfor

  call DepParserProcess(l:dp)
  let a:ctx.dependencies = []

  for l:dep in l:dp.closed
    if l:dep.objpath == ""
      call add(a:ctx.dependencies, l:dep)
    endif
  endfor

endfunction

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" SourceBuild
"
" Build the specified source file using its path and its generated object path.
" The "obj" folders for the files project are created if they do not exist.
" This runs the current compiler with the correct arguments. Finally update
" the dependencies of the file because we now have an up to date object but the
" included files might change in future.
"
" ctx - The source unit to compile into an object
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
function SourceBuild(ctx)

  "call Output("Building: " . a:ctx.name)
  "call Output("for Project: " . a:ctx.project.name)

  if !isdirectory("obj")
    call mkdir("obj")
  endif

  if !isdirectory("obj/" . a:ctx.project.name)
    call mkdir("obj/" . a:ctx.project.name)
  endif

  let l:cmd = s:compiler . " -c -o " . a:ctx.objpath . " -Isrc " . a:ctx.path
  call Output(l:cmd)
  let l:output = system(l:cmd)

  if l:output != ""
    call Output(l:output)
    throw "Build failure"
  endif

  call SourceUpdateDependencies(a:ctx)

endfunction

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" ProjectCreate
"
" Populate the project structure based on the details of the specified path.
" Scan the respective directory (not recursively) for any source and header
" files and add them to the correct list. Based on if any of those files were
" called "main" the executable flag will be set and generate a correct output
" filename for this project which will be used when building.
"
" iffe - The encapsulating parent system
" path - The relative path of the project
"
" Returns - The populated project structure
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
function ProjectCreate(iffe, path)

  let l:ctx = {}
  let l:ctx.path = a:path
  let l:ctx.name = fnamemodify(l:ctx.path, ':t')
  let l:ctx.absolutepath = fnamemodify(l:ctx.path, ':p:h')
  let l:ctx.sources = []
  let l:ctx.headers = []
  let l:ctx.executable = 0
  let l:files = globpath(l:ctx.path, '*')
  let l:files = split(l:files, '\n')

  for l:path in l:files

    if getftype(l:path) != "file"
      continue
    endif

    let l:file = FileCreate(l:ctx, l:path)

    if l:file.objpath == ""
      call add(l:ctx.headers, l:file)
      call add(a:iffe.headers, l:file)
    else
      call add(l:ctx.sources, l:file)
      call add(a:iffe.sources, l:file)
    endif

  endfor

  let l:suff = s:exeSuffix

  if l:suff != ""
    let l:suff = "." . l:suff
  endif

  if l:ctx.executable == 1
    let l:ctx.outpath = "bin/" . l:ctx.name . l:suff
  else
    let l:ctx.outpath = "lib/lib" . l:ctx.name . ".a"
  endif

  return l:ctx

endfunction

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" SourceRequiresBuild
"
" Ascertain whether the specified source unit requires a rebuild. This is done
" by checking if the timestamp of the file is more recent than the existing
" object or if any of its dependencies have a more recent timestamp.
"
" ctx - The source file to query
"
" Returns - 1 if the source requires a rebuild or 0 otherwise
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
function SourceRequiresBuild(ctx)

  " TODO: Testing
  "return 1

  let l:objtimestamp = getftime(a:ctx.objpath)

  if a:ctx.timestamp > l:objtimestamp
    return 1
  endif

  for l:dep in a:ctx.dependencies
    if l:dep.timestamp > l:objtimestamp
      return 1
    endif
  endfor

  return 0

endfunction

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" ProjectBuild
"
" All the sources belonging to the project are built. If any of the resulting
" objects are newer than the relevant executable or library file the project
" output is linked into an executable or archived into a library depending on
" the type. The "bin" or "lib" directory is created if it does not already
" exist.
"
" ctx - The specified project to build
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
function ProjectBuild(ctx)

  "call Output("Processing: " . a:ctx.name)
  let l:objstr = ""
  let l:newest = -1

  for l:source in a:ctx.sources

    if SourceRequiresBuild(l:source)
      call SourceBuild(l:source)
    endif

    let l:objstr = l:objstr . l:source.objpath . " "
    let l:objts = getftime(l:source.objpath)

    if l:objts > l:newest
      let l:newest = l:objts
    endif

  endfor

  if getftime(a:ctx.outpath) >= l:newest
    return
  endif

  if a:ctx.executable == 1

    if !isdirectory("bin")
      call mkdir("bin")
    endif

    let l:cmd = s:compiler . " -o " . a:ctx.outpath . " " . l:objstr
    call Output(l:cmd)
    let l:output = system(l:cmd)

    if l:output != ""
      call Output(l:output)
    endif
  else
    if !isdirectory("lib")
      call mkdir("lib")
    endif

    let l:cmd = "ar rcs " . a:ctx.outpath . " " . l:objstr
    call Output(l:cmd)
    let l:output = system(l:cmd)

    if l:output != ""
      call Output(l:output)
      throw "Build failure"
    endif
  endif

  call Output("")

endfunction

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" IffePopulateProjects
"
" Scan through the "src" directory for any folders. Assume that these are
" projects so process them and add them to the list.
"
" ctx - The encapsulated system
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
function IffePopulateProjects(ctx)

  let a:ctx.projects = []
  let a:ctx.sources = []
  let a:ctx.headers = []

  let l:files = globpath("src", '*')
  let l:files = split(l:files, '\n')

  for l:file in l:files
    if getftype(l:file) != "dir"
      continue
    endif

    let l:project = ProjectCreate(a:ctx, l:file)
    let l:project.iffe = a:ctx
    call add(a:ctx.projects, l:project)
  endfor

endfunction

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" IffeRestoreDependencies
"
" If the dependencies file exists, read through it whilst matching any source
" files with a name from the file. If any files match go through the list of
" dependencies from the file and if any header files match these names, then
" add them to the source file as a dependency. As a redundant check in case
" there are duplicate entries (there should not be), create a hash of any new
" dependencies and source and add it to a list to be subsequently checked to
" ensure that a source file does not receive the same dependency twice (same
" file name is fine so long as the path is different).
"
" ctx - The encapsulated system
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
function IffeRestoreDependencies(ctx)

  let l:added = []

  if !filereadable("obj/dependencies.iffe")
    return
  endif

  let l:lines = readfile("obj/dependencies.iffe")

  for l:line in l:lines
    let l:source = substitute(l:line, ': .*$', "", "")
    let l:dstr = substitute(l:line, '.*: ', "", "")
    let l:deps = split(l:dstr, ' ')

    "call Output("Deps: " . l:source)

    "for l:dep in l:deps
    "  call Output("Dep: " . l:dep)
    "endfor

    for l:s in a:ctx.sources
      if l:s.name != l:source
        continue
      endif

      "call Output("Source: " . l:s.name)

      for l:dep in l:deps
        for l:d in a:ctx.headers
          if l:d.name == l:dep

            let l:found = 0

            for l:a in l:added
              if l:a == l:s.path . " " . l:d.path
                let l:found = 1
                break
              endif
            endfor

            if l:found == 0
              "call Output("Source: " . l:s.name . " Dep: " . l:d.path)
              call add(l:added, l:s.path . " " . l:d.path)
              call add(l:s.dependencies, l:d)
            endif

          endif
        endfor
      endfor
    endfor
  endfor

endfunction

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" IffeCreate
"
" Output a small banner, create the encapsulated system structure and populate
" it with projects.
"
" Returns - The encapsulated system structure
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
function IffeCreate()

  let l:ctx = {}

  call Output("Iffe Build System")
  call Output("-----------------")

  call IffePopulateProjects(l:ctx)
  call IffeRestoreDependencies(l:ctx)

  return l:ctx

endfunction

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" IffeStoreDependencies
"
" For all of the sources, iterate through all of their dependencies and output
" their filenames into the dependencies file. The main thing to note is that
" a source with the same name but entirely different paths will actually share
" the same dependencies (to keep things simple and not depend on paths), so it
" is only necessary to output one of them. For this reason a list is created
" to store the processed sources and only the first time a source with a given
" name is encountered is it added to the file. The dependencies file is stored
" in the "obj" folder which is created if it does not already exist.
"
" ctx - The encapsulated system
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
function IffeStoreDependencies(ctx)

  let l:lines = []
  let l:seen = []

  for l:file in a:ctx.sources
    let l:out = "" . l:file.name . ":"
    let l:done = []
    let l:srcfound = 0

    for l:s in l:seen
      if l:s == l:file.name
        let l:srcfound = 1
        break
      endif
    endfor

    if l:srcfound == 1
      continue
    endif

    call add(l:seen, l:file.name)

    if len(l:file.dependencies) > 0
      for l:dep in l:file.dependencies
        let l:found = 0

        for l:d in l:done
          if l:d == l:dep.name
            let l:found = 1
            break
          endif
        endfor

        if l:found == 0
          let l:out = l:out . " " . l:dep.name
          call add(l:done, l:dep.name)
        endif
      endfor

      "call Output(l:file.name)
      "call Output(l:out)
      call add(l:lines, l:out)
    endif

  endfor

  if !isdirectory("obj")
    call mkdir("obj")
  endif

  call writefile(l:lines, "obj/dependencies.iffe", "b")

endfunction

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" IffeClean
"
" Recursively delete the "bin", "lib" and "obj" folders if any of them exist.
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
function IffeClean()

  if isdirectory("bin")
    call delete("bin", "rf")
  endif

  if isdirectory("lib")
    call delete("lib", "rf")
  endif

  if isdirectory("obj")
    call delete("obj", "rf")
  endif

endfunction

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" IffeBuild
"
" Iterate through all of the library projects and build them, then do the same
" for the executable projects. Finally store the updated dependencies from the
" source files into the database.
"
" ctx - The encapsulating system
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
function IffeBuild(ctx)

  for l:project in a:ctx.projects
    if l:project.executable == 0
      call ProjectBuild(l:project)
    endif
  endfor

  for l:project in a:ctx.projects
    if l:project.executable == 1
      call ProjectBuild(l:project)
    endif
  endfor

  call IffeStoreDependencies(a:ctx)

endfunction

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" IffeOptions
"
" Output a number of post build options and map them to buffer specific key
" presses.
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
function IffeOptions()

  call Output("-----------------")
  call Output("Press 'r' to rebuild")
  call Output("Press 'c' to clean")
  call Output("Press 'q' to exit")
  nnoremap <buffer> q :q!<CR>
  nnoremap <buffer> r :call IffeMain()<CR>
  nnoremap <buffer> c :call IffeClean()<CR>

endfunction

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" IffeMain
"
" Clear the buffer (in case it is a subsequent run), create the encapsulating
" structure and start the main processes. We do not want errors to escape here
" so everything in a try / catchall.
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
function IffeMain()

  try
    execute("normal! ggdG")
    let l:iffe = IffeCreate()
    call IffeBuild(l:iffe)
  catch
    call Output(v:exception)
  finally
    call IffeOptions()
  endtry

endfunction

call IffeMain()
