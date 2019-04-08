module SymbolServer

using Serialization, Pkg
include("from_static_lint.jl")

const storedir = abspath(joinpath(@__DIR__, "..", "..", "store"))
const c = Pkg.Types.Context()
const depot = create_depot(c, Dict{String,Any}())

if Sys.isunix()
    global const nullfile = "/dev/null"
elseif Sys.iswindows()
    global const nullfile = "nul"
else
    error("Platform not supported")
end

while true
    message, payload = deserialize(stdin)

    try
        if message == :debugmessage
            @info(payload)
            serialize(stdout, (:success, nothing))
        elseif message == :close
            break
        elseif message == :get_installed_packages_in_env
            pkgs = (VERSION < v"1.1.0-DEV.857" ? c.env.project["deps"] : Dict(name=>string(uuid) for (name,uuid) in c.env.project.deps))
            serialize(stdout, (:success, pkgs))
        elseif message == :get_core_packages
            core_pkgs = load_core()["packages"]
            SymbolServer.save_store_to_disc(core_pkgs["Base"], joinpath(storedir, "Base.jstore"))
            SymbolServer.save_store_to_disc(core_pkgs["Core"], joinpath(storedir, "Core.jstore"))
            serialize(stdout, (:success, nothing))
        elseif message == :get_all_packages_in_env
            pkgs = if VERSION < v"1.1.0-DEV.857"
                 Dict{String,Vector{String}}(n=>(p->get(p, "uuid", "")).(v) for (n,v) in c.env.manifest)
            else
                 Dict{String,Vector{String}}(v.name=>[string(n),] for (n,v) in c.env.manifest)
            end
            serialize(stdout, (:success, pkgs))
        elseif message == :load_package
            open(nullfile, "w") do f
                redirect_stdout(f) do # seems necessary incase packages print on startup
                    SymbolServer.import_package(payload, depot)
                end
            end
            for  (uuid, pkg) in depot["packages"]
                SymbolServer.save_store_to_disc(pkg, joinpath(storedir, "$uuid.jstore"))
            end
            serialize(stdout, (:success, collect(keys(depot["packages"]))))
        elseif message == :load_all
            for pkg in (VERSION < v"1.1.0-DEV.857" ? c.env.project["deps"] : c.env.project.deps)
                SymbolServer.import_package(pkg, depot)
            end
            for  (uuid, pkg) in depot["packages"]
                SymbolServer.save_store_to_disc(pkg, joinpath(storedir, "$uuid.jstore"))
            end
            serialize(stdout, (:success, collect(keys(depot["packages"]))))
        else
            serialize(stdout, (:failure, nothing))
        end
    catch err
        serialize(stdout, (:failure, err))
    end
end

end
