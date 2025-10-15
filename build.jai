is_absolute_path :: (path: string) -> bool {
    if !path return false;

    if path[0] == #char "/" return true;
    if path[0] == #char "\\" return true;
    if (path.count > 2) && (path[1] == #char ":") && (OS == .WINDOWS) return true;

    if path.count >= 3 {
        if path[1] == #char ":" return true;
    }

    return false;
}

build :: () {
    // Set working directory to the build file's location (project root)
    set_working_directory(#filepath);

    // Get the project root as an absolute path
    project_root := get_working_directory();

    w := compiler_create_workspace("Target Program");
    if !w {
        log_error("Workspace creation failed.\n");
        return;
    }

    args := get_build_options().compile_time_command_line;

    options := get_build_options(w);

    check_bindings   := true;
    do_check         := true;

    printed_help    := false;
    printed_version := false;

    files:         [..] string;
    array_add(*files, "src/main.jai");
    add_strings:   [..] string;
    run_strings:   [..] string;
    modules_paths: [..] string;
    array_add(*modules_paths, tprint("%/src/modules", project_root));

    user_arguments: [..] string;
    got_error       := false;

    output_executable_name: string;
    output_path:            string = tprint("%/build/", project_root);
    print("output_path %\n", output_path); 


    intercept_flags: Intercept_Flags;

    success, plugins_to_create, remaining_args := parse_plugin_arguments(args);
    if !success got_error = true;

    args = remaining_args;
    index := 0;
    while index < args.count {
        defer index += 1;

        it := args[index];

        if !it continue;

        if it[0] == #char "-" {
            if it == {
                case "-";
                    for i: index+1..args.count-1  array_add(*user_arguments, args[i]);
                    break;

                case "-release";
                    set_optimization(*options, .OPTIMIZED);
                    options.stack_trace = false;

                case "-very_release";
                    set_optimization(*options, .VERY_OPTIMIZED);
                    options.stack_trace = false;

                case "-very_debug";
                    set_optimization(*options, .VERY_DEBUG);

                case "-no_inline";
                    options.enable_bytecode_inliner = false;

                case "-quiet";
                    options.text_output_flags = 0;

                case "-x64";
                    options.backend = .X64;
                case "-llvm";
                    options.backend = .LLVM;

                case "-no_dce";
                    options.dead_code_elimination = .NONE;

                case "-no_split";
                    options.llvm_options.enable_split_modules = false;

                case "-output_ir";
                    options.llvm_options.output_llvm_ir_before_optimizations = true;
                    options.llvm_options.output_llvm_ir = true;

                case "-debug_for";
                    options.debug_for_expansions = true;

                case "-msvc_format";
                    options.use_visual_studio_message_format = true;

                case "-natvis";
                    options.use_natvis_compatible_types = true;

                case "-no_check";           do_check = false;
                case "-no_check_bindings";  check_bindings = false;
                case "-check_bindings";     check_bindings = true;

                case "-no_backtrace_on_crash";
                    options.backtrace_on_crash = .OFF;

                case "-version";
                    s := compiler_get_version_info(null);
                    print("Version: %.\n", s);
                    printed_version = true;

                case "-exe";
                    if index >= args.count-1 {
                        log_error("Command line: Missing argument to -exe.\n");
                        got_error = true;
                        break;
                    }

                    index += 1;
                    output_executable_name = args[index];

                case "-output_path";
                    if index >= args.count-1 {
                        log_error("Command line: Missing argument to -output_path.\n");
                        got_error = true;
                        break;
                    }

                    index += 1;
                    output_path = args[index];

                case "-add";

                    if index >= args.count-1 {
                        log_error("Command line: Missing argument to -add.\n");
                        got_error = true;
                        break;
                    }

                    index += 1;
                    array_add(*add_strings, args[index]);

                case "-run";

                    if index >= args.count-1 {
                        log_error("Command line: Missing argument to -run.\n");
                        got_error = true;
                        break;
                    }

                    index += 1;
                    array_add(*run_strings, args[index]);

                case "-help"; #through;
                case "-?";
                    log("%", HELP_STRING);

                    printed_help = true;

                case "-debugger";
                    options.interactive_bytecode_debugger = true;
                    set_build_options_dc(.{interactive_bytecode_debugger=true});

                case "-context_size";
                    if index >= args.count-1 {
                        log_error("Command line: Missing argument to -context_size.\n");
                        got_error = true;
                        break;
                    }

                    index += 1;

                    value, success := to_integer(args[index]);
                    if success {
                        CONTEXT_SIZE_MAX :: 0x4_0000;  // This has to be kind of reasonable because people declare Contexts on the stack and so forth...? Also must fit into 32 bits because that is the size of the value in Build_Options.
                        if value > CONTEXT_SIZE_MAX {
                            log_error("Command line: Invalid argument to -context_size. The context must be less than or equal to CONTEXT_SIZE_MAX, which is % (but the value provided was %). The size needs to be reasonable because contexts get declared on the stack, in other structs, and so forth. (If you think you should be able to exceed this limit, you can modify or replace Default_Metaprogram.)\n", CONTEXT_SIZE_MAX, value);
                        } else if value < size_of(Context_Base) {
                            log_error("Command line: Invalid argument to -context_size. The context must be at least as large as size_of(Context_Base), which is %.\n", size_of(Context_Base));
                        } else {
                            options.context_size_max = cast(s32) value;
                        }
                    } else {
                        log_error("Command line: Unable to parse an integer argument to context size; got '%'.\n", args[index]);
                    }
                case "-import_dir";
                    if index >= args.count-1 {
                        log_error("Command line: Missing argument to -import_dir.\n");
                        got_error = true;
                        break;
                    }

                    index += 1;
                    array_add(*modules_paths, args[index]);

                case "-no_color";
                    options.use_ansi_color = false;

                case "-verbose";
                    verbose = true;

                case;
                    log_error("Unknown argument '%'.\nExiting.\n", it);
                    got_error = true;
                    break;
            }

            continue;
        }

        array_add(*files, it);
    }

    if got_error {
        exit(1);
    }

    if do_check {
        p := array_add(*plugins_to_create);
        if check_bindings  p.name = "Check";
        else               p.name = "Check(CHECK_BINDINGS=false)";
    }

    success = init_plugins(plugins_to_create, *plugins, w);
    if !success {
        log_error("A plugin init() failed. Exiting.\n");
        exit(0);
    }

    if !(files || add_strings || run_strings) {
        if !(printed_help || printed_version)  log("You need to provide an argument telling the compiler what to compile! Sorry. Pass -help for help.\n");
        if printed_version && !printed_help exit(0);
        if !printed_help exit(1);
    }


    old_wd := get_working_directory();
    absolute_files: [..] string;
    if files {
        if output_path             options.output_path            = output_path;
        if output_executable_name  options.output_executable_name = output_executable_name;

        // Ensure output directory exists
        make_directory_if_it_does_not_exist(options.output_path);

        array_reserve(*absolute_files, files.count);
        for files {
            absolute_file := it;
            if !is_absolute_path(it) {
                #if OS == .WINDOWS {
                    absolute_file = get_absolute_path(it);
                } else {
                    absolute_file = sprint("%/%", old_wd, it);
                }
            }

            array_add(*absolute_files, absolute_file);
        }

        basename, path := get_basename_and_path(absolute_files[0]);

        if basename || path {
            if path && !output_path {
                options.output_path = path;
                if verbose print("options.output_path = \"%\";\n", path);
            }

            if basename && !output_executable_name {
                options.output_executable_name = basename;
                if verbose print("options.output_executable_name = \"%\";\n", basename);
            }
        }

        // Stay at project root so output goes to build/ instead of src/build/
    }

    if printed_help {
        log("\n\n");

        for plugins {
            name := plugins_to_create[it_index].name;

            if it.log_help {
                log("---- Help for plugin '%': ----\n\n", name);
                it.log_help(it);
                log("\n");
            } else {
                log("---- Plugin '%' provides no help.\n", name);
            }
        }

        if !(files || run_strings) exit(0);
    }

    if modules_paths {
        array_add(*modules_paths, ..options.import_path);
        options.import_path = modules_paths;
    }

    options.compile_time_command_line = user_arguments;

    loc: Source_Code_Location;
    loc.fully_pathed_filename = ifx absolute_files then absolute_files[0] else tprint("%/fake_file.fake", old_wd);

    set_build_options(options, w, loc=loc);

    for plugins if it.before_intercept it.before_intercept(it, *intercept_flags);

    compiler_begin_intercept(w, intercept_flags);

    if verbose {
        print("Input files: %\n", absolute_files);
        print("Add strings: %\n", add_strings);
        print("Run strings: %\n", run_strings);
        print("Plugins:     %\n", plugins_to_create);
    }

    for plugins      if it.add_source it.add_source(it);

    for absolute_files {
        add_build_file(it, w);
    }

    for add_strings  add_build_string(tprint("%;", it), w);
    for run_strings  add_build_string(tprint("#run %;\n", it), w);

    message_loop(w);
    compiler_end_intercept(w);

    for plugins if it.finish   it.finish  (it);
    for plugins if it.shutdown it.shutdown(it);

    set_build_options_dc(.{do_output=false, write_added_strings=false});
}

#run,stallable build();

message_loop :: (w: Workspace) {
    while true {
        message := compiler_wait_for_message();
        for plugins if it.message it.message(it, message);
        if message.kind == .COMPLETE break;
    }
}

#import "Basic";
#import "File";
#import "Compiler";
#import "Metaprogram_Plugins";


verbose  := false;
plugins: [..] *Metaprogram_Plugin;


HELP_STRING :: #string DONE
Available Command-Line Arguments:

-add arg         Add the string 'arg' to the target program as code.
                 Example: -add "MY_VARIABLE :: 42";
-context_size n  Set the size of #Context, in bytes (you only need this if your program has a really big context).
                 Example: -context_size 2048
-debugger        If there is a crash in compile-time execution, drop into the interactive debugger.
-debug_for       Enable debugging of for_expansion macros. (Otherwise the debugger will never step into them to make stepping through for loops more convenient.)
-exe name        Set output_executable_name on the target workspace to 'name'.
-import_dir arg  Add this directory to the list of directories searched by #import. Can be
                     used multiple times.
-llvm            Use the LLVM backend by default (unless overridden by a metaprogram).
                     The LLVM backend is the default normally, so this isn't too useful.
-msvc_format     Use Visual Studio's message format for error messages.
-natvis          Use natvis compatible type names in debug info (array<T> instead of [] T, etc).
-no_backtrace_on_crash    Do not catch OS-level exceptions and print a stack trace when your program crashes.
                     Causes less code to be imported on startup. Depending on your OS (for example, on Windows),
                     crashes may look like silent exits.
-no_color        Disable ANSI terminal coloring in output messages.
-no_dce          Turn off dead code elimination. This is a temporary option,
                     provided because dead code elimination is a new and potentially
                     unstable feature. This will eventually be removed; the preferred way
                     to turn off dead code elimination is via Build_Options.
-no_split        Disable split modules when compiling with the LLVM backend.
-no_check        Do not import modules/Check and run it on the code. The result will be that you won't get
                     augmented error checking for stuff like print() calls. Use this if you want to substitute
                     your own error checking plugin, or for higher speeds in builds known to be good.
-no_check_bindings Disable checking of module bindings when running modules/Check. If modules/Check is not run
                     due to -no_check, this does nothing.
-no_inline       Disable inlining throughout the program (useful when debugging).
-output_path     Set the path where your output files (such as the executable) will go.
-quiet           Run the compiler in quiet mode (not outputting unnecessary text).
-release         Build a release build, i.e., tell the default metaprogram to disable stack traces and enable optimizations.
-very_release    Build with maximum optimizations (.VERY_OPTIMIZED) and no stack traces.
-run arg         Start a #run directive that parses and runs 'arg' as code.
                     Example: -run write_string(\"Hello!\n\")
                     (The extra backslashes are the shell's fault.)
-verbose         Output some extra information about what this metaprogram is doing.
-version         Print the version of the compiler.
-very_debug      Build a very_debug build, i.e. add more debugging facilities than usual, which will cause it to run slower but catch more problems.
-x64             Use the x64 backend by default (unless overridden by a metaprogram).

-                Every argument after - is ignored by the compiler itself,
                     and is passed to the user-level metaprogram for its own use.

Any argument not starting with a -, and before a - by itself, is the name of a file to compile.

Example:    jai -x64 program.jai - info for -the compile_time execution


==== Plugins ====

In the section before the lone dash, but after all other such arguments listed above,
you can have arguments that invoke plugins. These arguments begin with a + and then
the name of the plugin module to invoke.

Example:    jai -x64 program.jai -verbose +Icon -icon icon_filename.ico +Autorun

Each + invokes a new plugin, and all arguments between that + and the next + are sent
to that plugin. In the above example, the -icon is a command-line option handled only
by the Icon plugin (the name "-icon" is currently confusing and we'll change it!)

Here's an example that uses the lone dash as well as a plugin invocation:

Example:    jai -x64 program.jai +Icon -icon icon_filename.ico +Autorun - arguments for the invoked metaprogram go here


==== Compiler Hardcoded Options ====

There are also a few very tweaky compiler-front-end options that almost nobody
will ever care about. To see these, do:

            jai -- help


==== Other Functionality ====

Unlike most contemporary compilers, we don't have a huge number of arcane arguments
to control all kinds of minute things, that you have to spend a long time learning about.
Our philosophy is, it's much more effective to do configuration from code, where
you have a great deal of precise control over what's happening, options can be expressed
as easy-to-understand data structures, and so forth. To get started, look into Build_Options
in modules/Compiler/Compiler.jai, or look at how_to/400_workspaces.jai and
how_to/420_command_line.jai.

This text is generated by modules/Default_Metaprogram.jai, the code that starts up
when you run the compiler. You can read the text of this file to learn how all this works
(it's pretty simple!); you can make a copy of Default_Metaprogram and modify it
to work however you want.
DONE


