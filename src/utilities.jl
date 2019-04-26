Lar = LinearAlgebraicRepresentation

"""
    bbox(vertices::Points)

The axis aligned bounding box of the provided set of n-dim `vertices`.

The box is returned as the couple of `Points` of the two opposite corners of the box.
"""
function bbox(vertices::Points)
    minimum = mapslices(x->min(x...), vertices, dims=1)
    maximum = mapslices(x->max(x...), vertices, dims=1)
    minimum, maximum
end

"""
    bbox_contains(container, contained)

Check if the axis aligned bounding box `container` contains `contained`.

Each input box must be passed as the couple of `Points` standing on the opposite corners of the box.
"""
function bbox_contains(container, contained)
    b1_min, b1_max = container
    b2_min, b2_max = contained
    all(map((i,j,k,l)->i<=j<=k<=l, b1_min, b2_min, b2_max, b1_max))
end

"""
    face_area(V::Points, EV::Cells, face::Cell)

The area of `face` given a geometry `V` and an edge topology `EV`.
"""
function face_area(V::Points, EV::Cells, face::Cell)
    return face_area(V, build_copEV(EV), face)
end

function face_area(V::Points, EV::ChainOp, face::Cell)
    function triangle_area(triangle_points::Points)
        ret = ones(3,3)
        ret[:, 1:2] = triangle_points
        return .5*det(ret)
    end

    area = 0

    fv = buildFV(EV, face)

    verts_num = length(fv)
    v1 = fv[1]

    for i in 2:(verts_num-1)

        v2 = fv[i]
        v3 = fv[i+1]

        area += triangle_area(V[[v1, v2, v3], :])
    end

    return area
end

"""
    skel_merge(V1::Points, EV1::ChainOp, V2::Points, EV2::ChainOp)

Merge two **1-skeletons**
"""
function skel_merge(V1::Points, EV1::ChainOp, V2::Points, EV2::ChainOp)
    V = [V1; V2]
    EV = blockdiag(EV1,EV2)
    return V, EV
end

"""
    skel_merge(V1::Points, EV1::ChainOp, FE1::ChainOp, V2::Points, EV2::ChainOp, FE2::ChainOp)

Merge two **2-skeletons**
"""
function skel_merge(V1::Points, EV1::ChainOp, FE1::ChainOp, V2::Points, EV2::ChainOp, FE2::ChainOp)
    FE = blockdiag(FE1,FE2)
    V, EV = skel_merge(V1, EV1, V2, EV2)
    return V, EV, FE
end

"""
    delete_edges(todel, V::Points, EV::ChainOp)

Delete edges and remove unused vertices from a **2-skeleton**.

Loop over the `todel` edge index list and remove the marked edges from `EV`.
The vertices in `V` which remained unconnected after the edge deletion are deleted too.
"""
function delete_edges(todel, V::Points, EV::ChainOp)
    tokeep = setdiff(collect(1:EV.m), todel)
    EV = EV[tokeep, :]
    
    vertinds = 1:EV.n
    todel = Array{Int64, 1}()
    for i in vertinds
        if length(EV[:, i].nzind) == 0
            push!(todel, i)
        end
    end

    tokeep = setdiff(vertinds, todel)
    EV = EV[:, tokeep]
    V = V[tokeep, :]

    return V, EV
end




"""
    buildFV(EV::Cells, face::Cell)

The list of vertex indices that expresses the given `face`.

The returned list is made of the vertex indices ordered following the traversal order to keep a coherent face orientation. 
The edges are need to understand the topology of the face.

In this method the input face must be expressed as a `Cell`(=`SparseVector{Int8, Int}`) and the edges as `Cells`.
"""
function buildFV(EV::Cells, face::Cell)
    return buildFV(build_copEV(EV), face)
end

"""
    buildFV(copEV::ChainOp, face::Cell)

The list of vertex indices that expresses the given `face`.

The returned list is made of the vertex indices ordered following the traversal order to keep a coherent face orientation. 
The edges are need to understand the topology of the face.

In this method the input face must be expressed as a `Cell`(=`SparseVector{Int8, Int}`) and the edges as `ChainOp`.
"""
function buildFV(copEV::ChainOp, face::Cell)
    startv = -1
    nextv = 0
    edge = 0

    vs = Array{Int64, 1}()

    while startv != nextv
        if startv < 0
            edge = face.nzind[1]
            startv = copEV[edge,:].nzind[face[edge] < 0 ? 2 : 1]
            push!(vs, startv)
        else
            edge = setdiff(intersect(face.nzind, copEV[:, nextv].nzind), edge)[1]
        end
        nextv = copEV[edge,:].nzind[face[edge] < 0 ? 1 : 2]
        push!(vs, nextv)

    end

    return vs[1:end-1]
end

"""
    buildFV(copEV::ChainOp, face::Array{Int, 1})

The list of vertex indices that expresses the given `face`.

The returned list is made of the vertex indices ordered following the traversal order to keep a coherent face orientation. 
The edges are need to understand the topology of the face.

In this method the input face must be expressed as a list of vertex indices and the edges as `ChainOp`.
"""
function buildFV(copEV::ChainOp, face::Array{Int, 1})
    startv = face[1]
    nextv = startv

    vs = []
    visited_edges = []

    while true
        curv = nextv
        push!(vs, curv)

        edge = 0

        for edgeEx in copEV[:, curv].nzind
            nextv = setdiff(copEV[edgeEx, :].nzind, curv)[1]
            if nextv in face && (nextv == startv || !(nextv in vs)) && !(edgeEx in visited_edges)
                edge = edgeEx
                break
            end
        end

        push!(visited_edges, edge)

        if nextv == startv
            break
        end
    end

    return vs
end


"""
    build_copFE(FV::Cells, EV::Cells)

The signed `ChainOp` from 1-cells (edges) to 2-cells (faces)
"""
function build_copFE(FV::Cells, EV::Cells)
    faces = []

    for face in FV
        f = []
        for (i,v) in enumerate(face)
            edge = [v, face[(i==length(face)) ? 1 : i+1]]
            ord_edge = sort(edge)

            edge_idx = findfirst(e->e==ord_edge, EV)

            push!(f, (edge_idx, sign(edge[2]-edge[1])))
        end
        
        push!(faces, f)
    end

    FE = spzeros(Int8, length(faces), length(EV))

    for (i,f) in enumerate(faces)
        for e in f
            FE[i, e[1]] = e[2]
        end
    end

    return FE
end

"""
    build_copEV(EV::Cells, signed=true)

The signed (or not) `ChainOp` from 0-cells (vertices) to 1-cells (edges)
"""
function build_copEV(EV::Cells, signed=true)
    setValue = [-1, 1]
    if signed == false
        setValue = [1, 1]
    end

    maxv = max(map(x->max(x...), EV)...)
    copEV = spzeros(Int8, length(EV), maxv)

    for (i,e) in enumerate(EV)
        e = sort(collect(e))
        copEV[i, e] = setValue
    end

    return copEV
end

"""
    build_cops(edges::Cells, faces::Cells)

The vertices-edges and edges-faces chain operators (`copEV::ChainOp`, `copFE::ChainOp`)
"""
function build_cops(edges::Cells, faces::Cells)
    copEV = build_copEV(edges)
    FV = Cells(map(x->buildFV(copEV,x), faces))
    copFE = build_copFE(FV, edges)

    return [copEV, copFE]
end

"""
    vin(vertex, vertices_set)

Checks if `vertex` is one of the vertices inside `vertices_set`
"""
function vin(vertex, vertices_set)
    for v in vertices_set
        if vequals(vertex, v)
            return true
        end
    end
    return false
end

"""
    vequals(v1, v2)

Check the equality between vertex `v1` and vertex `v2`
"""
function vequals(v1, v2)
    err = 10e-8
    return length(v1) == length(v2) && all(map((x1, x2)->-err < x1-x2 < err, v1, v2))
end

"""
    triangulate(model::LARmodel)

Full constrained Delaunnay triangulation of the given 3-dimensional `LARmodel`
"""
function triangulate(model::LARmodel)
    V, topology = model
    cc = build_cops(topology...)
    return triangulate(V, cc)
end

"""
    triangulate(V::Points, cc::ChainComplex)

Full constrained Delaunnay triangulation of the given 3-dimensional model (given with topology as a `ChainComplex`)
"""
function triangulate(V::Points, cc::ChainComplex)
    copEV, copFE = cc

    triangulated_faces = Array{Any, 1}(undef, copFE.m)

	function vcycle( copEV::Lar.ChainOp, copFE::Lar.ChainOp, f::Int64 )
		edges,signs = findnz(copFE[f,:])
		vpairs = [s>0 ? findnz(copEV[e,:])[1] : reverse(findnz(copEV[e,:])[1]) 
					for (e,s) in zip(edges,signs)]
		vdict = Dict((v1,v2) for (v1,v2) in  vpairs)
	
		v0 = collect(vdict)[1][1]
		chain_0 = Int64[v0]
		v = vdict[v0]
		while v ≠ v0 
			push!(chain_0,v)
			v = vdict[v]
		end
		return chain_0
	end

    for f in 1:copFE.m
        if f % 10 == 0
            print(".")
        end
        
        edges_idxs = copFE[f, :].nzind
        edge_num = length(edges_idxs)
        edges = zeros(Int64, edge_num, 2)

        
        #fv = Lar.buildFV(copEV, copFE[f, :])
        fv = vcycle(copEV, copFE, f)

        vs = V[fv, :]

        v1 = normalize(vs[2, :] - vs[1, :])
        v2 = [0 0 0]
        v3 = [0 0 0]
        err = 1e-8
        i = 3
        while -err < norm(v3) < err
            v2 = normalize(vs[i, :] - vs[1, :])
            v3 = cross(v1, v2)
            i = i + 1
        end
        M = reshape([v1; v2; v3], 3, 3)

        vs = (vs*M)[:, 1:2]
        
        for i in 1:length(fv)
            edges[i, 1] = fv[i]
            edges[i, 2] = i == length(fv) ? fv[1] : fv[i+1]
        end
        
        triangulated_faces[f] = 
        	Triangle.constrained_triangulation(vs, fv, edges, fill(true, edge_num))

        tV = (V*M)[:, 1:2]
       
        area = face_area(tV, copEV, copFE[f, :])
        if area < 0 
            for i in 1:length(triangulated_faces[f])
                triangulated_faces[f][i] = triangulated_faces[f][i][end:-1:1]
            end
        end
    end

    return triangulated_faces
end

"""
    point_in_face(point, V::Points, copEV::ChainOp)

Check if `point` is inside the area of the face bounded by the edges in `copEV`
"""
function point_in_face(point, V::Points, copEV::ChainOp)

    function pointInPolygonClassification(V,EV)

        function crossingTest(new, old, status, count)
        if status == 0
            status = new
            return status, (count + 0.5)
        else
            if status == old
                return 0, (count + 0.5)
            else
                return 0, (count - 0.5)
            end
        end
        end

        function setTile(box)
        tiles = [[9,1,5],[8,0,4],[10,2,6]]
        b1,b2,b3,b4 = box
        function tileCode(point)
            x,y = point
            code = 0
            if y>b1 code=code|1 end
            if y<b2 code=code|2 end
            if x>b3 code=code|4 end
            if x<b4 code=code|8 end
            return code
        end
        return tileCode
        end

        function pointInPolygonClassification0(pnt)
            x,y = pnt
            xmin,xmax,ymin,ymax = x,x,y,y
            tilecode = setTile([ymax,ymin,xmax,xmin])
            count,status = 0,0

            for k in 1:EV.m
                edge = EV[k,:]
                p1, p2 = V[edge.nzind[1], :], V[edge.nzind[2], :]
                (x1,y1),(x2,y2) = p1,p2
                c1,c2 = tilecode(p1),tilecode(p2)
                c_edge, c_un, c_int = xor(c1, c2), c1|c2, c1&c2
                
                if (c_edge == 0) & (c_un == 0) return "p_on" 
                elseif (c_edge == 12) & (c_un == c_edge) return "p_on"
                elseif c_edge == 3
                    if c_int == 0 return "p_on"
                    elseif c_int == 4 count += 1 end
                elseif c_edge == 15
                    x_int = ((y-y2)*(x1-x2)/(y1-y2))+x2 
                    if x_int > x count += 1
                    elseif x_int == x return "p_on" end
                elseif (c_edge == 13) & ((c1==4) | (c2==4))
                        status, count = crossingTest(1,2,status,count)
                elseif (c_edge == 14) & ((c1==4) | (c2==4))
                        status, count = crossingTest(2,1,status,count)
                elseif c_edge == 7 count += 1
                elseif c_edge == 11 count = count
                elseif c_edge == 1
                    if c_int == 0 return "p_on"
                    elseif c_int == 4 
                        status, count = crossingTest(1,2,status,count) 
                    end
                elseif c_edge == 2
                    if c_int == 0 return "p_on"
                    elseif c_int == 4 
                        status, count = crossingTest(2,1,status,count) 
                    end
                elseif (c_edge == 4) & (c_un == c_edge) return "p_on"
                elseif (c_edge == 8) & (c_un == c_edge) return "p_on"
                elseif c_edge == 5
                    if (c1==0) | (c2==0) return "p_on"
                    else 
                        status, count = crossingTest(1,2,status,count) 
                    end
                elseif c_edge == 6
                    if (c1==0) | (c2==0) return "p_on"
                    else 
                        status, count = crossingTest(2,1,status,count) 
                    end
                elseif (c_edge == 9) & ((c1==0) | (c2==0)) return "p_on"
                elseif (c_edge == 10) & ((c1==0) | (c2==0)) return "p_on"
                end
            end
            
            if (round(count)%2)==1 
                return "p_in"
            else 
                return "p_out"
            end
        end
        return pointInPolygonClassification0
    end
    
    return pointInPolygonClassification(V, copEV)(point) == "p_in"
end

"""
    lar2obj(V::Points, cc::ChainComplex)

Triangulated OBJ string representation of the model passed as input.

Use this function to export LAR models into OBJ

# Example

```julia
	julia> cube_1 = ([0 0 0 0 1 1 1 1; 0 0 1 1 0 0 1 1; 0 1 0 1 0 1 0 1], 
	[[1,2,3,4],[5,6,7,8],[1,2,5,6],[3,4,7,8],[1,3,5,7],[2,4,6,8]], 
	[[1,2],[3,4],[5,6],[7,8],[1,3],[2,4],[5,7],[6,8],[1,5],[2,6],[3,7],[4,8]] )
	
	julia> cube_2 = Lar.Struct([Lar.t(0,0,0.5), Lar.r(0,0,pi/3), cube_1])
	
	julia> V, FV, EV = Lar.struct2lar(Lar.Struct([ cube_1, cube_2 ]))
	
	julia> V, bases, coboundaries = Lar.chaincomplex(V,FV,EV)
	
	julia> (EV, FV, CV), (copEV, copFE, copCF) = bases, coboundaries

	julia> FV # bases[2]
	18-element Array{Array{Int64,1},1}:
	 [1, 3, 4, 6]            
	 [2, 3, 5, 6]            
	 [7, 8, 9, 10]           
	 [1, 2, 3, 7, 8]         
	 [4, 6, 9, 10, 11, 12]   
	 [5, 6, 11, 12]          
	 [1, 4, 7, 9]            
	 [2, 5, 11, 13]          
	 [2, 8, 10, 11, 13]      
	 [2, 3, 14, 15, 16]      
	 [11, 12, 13, 17]        
	 [11, 12, 13, 18, 19, 20]
	 [2, 3, 13, 17]          
	 [2, 13, 14, 18]         
	 [15, 16, 19, 20]        
	 [3, 6, 12, 15, 19]      
	 [3, 6, 12, 17]          
	 [14, 16, 18, 20]        

	julia> CV # bases[3]
	3-element Array{Array{Int64,1},1}:
	 [2, 3, 5, 6, 11, 12, 13, 14, 15, 16, 18, 19, 20]
	 [2, 3, 5, 6, 11, 12, 13, 17]                    
	 [1, 2, 3, 4, 6, 7, 8, 9, 10, 11, 12, 13, 17]    
	 
	julia> copEV # coboundaries[1]
	34×20 SparseMatrixCSC{Int8,Int64} with 68 stored entries: ...

	julia> copFE # coboundaries[2]
	18×34 SparseMatrixCSC{Int8,Int64} with 80 stored entries: ...
	
	julia> copCF # coboundaries[3]
	4×18 SparseMatrixCSC{Int8,Int64} with 36 stored entries: ...
	
	objs = Lar.lar2obj(V'::Lar.Points, [coboundaries...])
			
	open("./two_cubes.obj", "w") do f
    	write(f, objs)
	end


```
"""
function lar2obj(V::Points, cc::ChainComplex)
    copEV, copFE, copCF = cc

    obj = ""
    for v in 1:size(V, 1)
        obj = string(obj, "v ", 
        	round(V[v, 1], digits=6), " ", 
        	round(V[v, 2], digits=6), " ", 
        	round(V[v, 3], digits=6), "\n")
    end

    print("Triangulating")
    triangulated_faces = triangulate(V, cc[1:2])
    println("DONE")

    for c in 1:copCF.m
        obj = string(obj, "\ng cell", c, "\n")
        for f in copCF[c, :].nzind
            triangles = triangulated_faces[f]
            for tri in triangles
                t = copCF[c, f] > 0 ? tri : tri[end:-1:1]
                obj = string(obj, "f ", t[1], " ", t[2], " ", t[3], "\n")
            end
        end
    end

    return obj
end


"""
    obj2lar(path)

Read OBJ file at `path` and create a 2-skeleton as `Tuple{Points, ChainComplex}` from it.

This function does not care about eventual internal grouping inside the OBJ file.
"""
function obj2lar(path)
    vs = Array{Float64, 2}(undef, 0, 3)
    edges = Array{Array{Int, 1}, 1}()
    faces = Array{Array{Int, 1}, 1}()

    open(path, "r") do fd
        for line in eachline(fd)
            elems = split(line)
            if length(elems) > 0
                if elems[1] == "v"

                    x = parse(Float64, elems[2])
                    y = parse(Float64, elems[3])
                    z = parse(Float64, elems[4])
                    vs = [vs; x y z]

                elseif elems[1] == "f"
                    # Ignore the vertex tangents and normals
                    v1 = parse(Int, split(elems[2], "/")[1])
                    v2 = parse(Int, split(elems[3], "/")[1])
                    v3 = parse(Int, split(elems[4], "/")[1])

                    e1 = sort([v1, v2])
                    e2 = sort([v2, v3])
                    e3 = sort([v1, v3])

                    if !(e1 in edges)
                        push!(edges, e1)
                    end
                    if !(e2 in edges)
                        push!(edges, e2)
                    end
                    if !(e3 in edges)
                        push!(edges, e3)
                    end

                    push!(faces, sort([v1, v2, v3]))
                end
            end
        end
    end

    return vs, build_cops(edges, faces)
end

"""
    binaryRange(n)

Generate the first `n` binary numbers in string padded for max `2^n` length
"""
function binaryRange(n) 
    return string.(range(0, length=2^n), base=2, pad=n)
end


function space_arrangement(V::Points, EV::ChainOp, FE::ChainOp, multiproc::Bool=false)

    fs_num = size(FE, 1)
    sp_idx = Lar.Arrangement.spatial_index(V, EV, FE)

    global rV = Lar.Points(undef, 0,3)
    global rEV = SparseArrays.spzeros(Int8,0,0)
    global rFE = SparseArrays.spzeros(Int8,0,0)
    
    if (multiproc == true)
        in_chan = Distributed.RemoteChannel(()->Channel{Int64}(0))
        out_chan = Distributed.RemoteChannel(()->Channel{Tuple}(0))
        
        @async begin
            for sigma in 1:fs_num
                put!(in_chan, sigma)
            end
            for p in Distributed.workers()
                put!(in_chan, -1)
            end
        end
        
        for p in Distributed.workers()
            @async Base.remote_do(
                frag_face_channel, p, in_chan, out_chan, V, EV, FE, sp_idx)
        end
        
        for sigma in 1:fs_num
            rV, rEV, rFE = skel_merge(rV, rEV, rFE, take!(out_chan)...)
        end
        
    else

       for sigma in 1:fs_num
           # print(sigma, "/", fs_num, "\r")
           nV, nEV, nFE = Lar.Arrangement.frag_face(
           	V, EV, FE, sp_idx, sigma)
           a,b,c = Lar.skel_merge(
           	rV, rEV, rFE, nV, nEV, nFE)
           global rV=a; global rEV=b; global rFE=c
       end

#		depot_V = Array{Array{Float64,2},1}(undef,fs_num)
#		depot_EV = Array{ChainOp,1}(undef,fs_num)
#		depot_FE = Array{ChainOp,1}(undef,fs_num)
#        for sigma in 1:fs_num
#            print(sigma, "/", fs_num, "\r")
#            nV, nEV, nFE = Arrangement.frag_face( V, EV, FE, sp_idx, sigma)
#            depot_V[sigma] = nV
#            depot_EV[sigma] = nEV
#            depot_FE[sigma] = nFE
#        end
#		rV = vcat(depot_V...)
#		rEV = SparseArrays.blockdiag(depot_EV...)
#		rFE = SparseArrays.blockdiag(depot_FE...)
    
    end

    rV, rEV, rFE = Lar.Arrangement.merge_vertices(rV, rEV, rFE)
    
    rCF = Arrangement.minimal_3cycles(rV, rEV, rFE)

    return rV, rEV, rFE, rCF
end



###  2D triangulation
Lar = LinearAlgebraicRepresentation
""" 
	obj2lar2D(path::AbstractString)::Lar.LARmodel

Read a *triangulation* from file, given its `path`. Return a `LARmodel` object
"""
function obj2lar2D(path::AbstractString)::Lar.LARmodel
    vs = Array{Float64, 2}(undef, 0, 3)
    edges = Array{Array{Int, 1}, 1}()
    faces = Array{Array{Int, 1}, 1}()

    open(path, "r") do fd
		for line in eachline(fd)
			elems = split(line)
			if length(elems) > 0
				if elems[1] == "v"
					x = parse(Float64, elems[2])
					y = parse(Float64, elems[3])
					z = parse(Float64, elems[4])
					vs = [vs; x y z]
				elseif elems[1] == "f"
					# Ignore the vertex tangents and normals
					v1 = parse(Int, elems[2])
					v2 = parse(Int, elems[3])
					v3 = parse(Int, elems[4])
					append!(edges, map(sort,[[v1,v2],[v2,v3],[v3,v1]]))
					push!(faces, [v1, v2, v3])
				end
				edges = collect(Set(edges))
			end
		end
	end
    return (vs, [edges,faces])::Lar.LARmodel
end


""" 
	lar2obj2D(V::Lar.Points, 
			cc::Lar.ChainComplex)::String

Produce a *triangulation* from a `LARmodel`. Return a `String` object
"""
function lar2obj2D(V::Lar.Points, cc::Lar.ChainComplex)::String
    @assert length(cc) == 2
    copEV, copFE = cc
    V = [V zeros(size(V, 1))]

    global obj = ""
    for v in 1:size(V, 1)
        	global obj = string(obj, "v ", 
        	round(V[v, 1]; digits=6), " ", 
        	round(V[v, 2]; digits=6), " ", 
        	round(V[v, 3]; digits=6), "\n")
    end

    #triangulated_faces = triangulate2D(V, cc)
    triangulated_faces = triangulate(V, cc)

	obj = string(obj, "\n")
	for f in 1:copFE.m
		triangles = triangulated_faces[f]
		for tri in triangles
			t = tri
			#t = copCF[c, f] > 0 ? tri : tri[end:-1:1]
			obj = string(obj, "f ", t[1], " ", t[2], " ", t[3], "\n")
		end
	end

    return obj
end


#TODO: finish by using a string as an IObuffer
#"""
#	lar2tria2lar(V::Lar.Points, cc::Lar.ChainComplex)::Lar.LARmodel
#	
#Return a triangulated `LARmodel` starting from a stadard LARmodel.
#Useful for colour drawing a complex of non-convex cells.
#
#"""
#function lar2tria2lar(V::Lar.Points, cc::Lar.ChainComplex)::Lar.LARmodel
#	obj = Lar.lar2obj2D(V::Lar.Points, cc::Lar.ChainComplex)
#	vs, (edges,faces) = Lar.obj2lar2D(obj::AbstractString)::Lar.LARmodel
#	return (vs, [edges,faces])::Lar.LARmodel
#end




""" 
	triangulate2D(V::Lar.Points, 
			cc::Lar.ChainComplex)::Array{Any, 1}

Compute a *CDT* for each face of a `ChainComplex`. Return an `Array` of triangles.
"""
function triangulate2D(V::Lar.Points, cc::Lar.ChainComplex)::Array{Any, 1}
    copEV, copFE = cc
    triangulated_faces = Array{Any, 1}(undef, copFE.m)
    if size(V,2)==2 
		V = [V zeros(size(V,1),1)]
	end
	
    for f in 1:copFE.m   
        edges_idxs = copFE[f, :].nzind
        edge_num = length(edges_idxs)
        edges = Array{Int64,1}[] #zeros(Int64, edge_num, 2)

        fv = Lar.buildFV(copEV, copFE[f, :])
        vs = V[fv, :]
        
        for i in 1:length(fv)
        	edge = Int64[0,0]
            edge[1] = fv[i]
            edge[2] = i == length(fv) ? fv[1] : fv[i+1]
            push!(edges,edge::Array{Int64,1})
        end
        edges = hcat(edges...)'
        edges = convert(Array{Int64,2}, edges)
        
        triangulated_faces[f] = Triangle.constrained_triangulation(
        vs, fv, edges, fill(true, edge_num))
        tV = V[:, 1:2]
        
        area = Lar.face_area(tV, copEV, copFE[f, :])
        if area < 0 
            for i in 1:length(triangulated_faces[f])
                triangulated_faces[f][i] = triangulated_faces[f][i][end:-1:1]
            end
        end
    end

    return triangulated_faces
end


"""
	lar2cop(CV::Lar.Cells)::Lar.ChainOp

Convert an array of array of integer indices to vertices into a sparse matrix.

# Examples

For a single 3D unit cube we get:

```
julia> V,(VV,EV,FV,CV) = Lar.cuboid([1,1,1],true);

julia> Matrix(Lar.lar2cop(EV))
12×8 Array{Int8,2}:
 1  1  0  0  0  0  0  0
 0  0  1  1  0  0  0  0
 0  0  0  0  1  1  0  0
 0  0  0  0  0  0  1  1
 1  0  1  0  0  0  0  0
 0  1  0  1  0  0  0  0
 0  0  0  0  1  0  1  0
 0  0  0  0  0  1  0  1
 1  0  0  0  1  0  0  0
 0  1  0  0  0  1  0  0
 0  0  1  0  0  0  1  0
 0  0  0  1  0  0  0  1

julia> Matrix(Lar.lar2cop(FV))
6×8 Array{Int8,2}:
 1  1  1  1  0  0  0  0
 0  0  0  0  1  1  1  1
 1  1  0  0  1  1  0  0
 0  0  1  1  0  0  1  1
 1  0  1  0  1  0  1  0
 0  1  0  1  0  1  0  1

julia> Matrix(Lar.lar2cop(CV))
1×8 Array{Int8,2}:
 1  1  1  1  1  1  1  1
```
"""
function lar2cop(CV::Lar.Cells)::Lar.ChainOp
	I = Int64[]; J = Int64[]; Value = Int8[]; 
	for k=1:size(CV,1)
		n = length(CV[k])
		append!(I, k * ones(Int64, n))
		append!(J, CV[k])
		append!(Value, ones(Int64, n))
	end
	return SparseArrays.sparse(I,J,Value)
end


"""
	cop2lar(cop::Lar.ChainOp)::Lar.Cells

Convert a sparse array of type `ChainOp` into an array of array of type `Cells`.

Notice that `cop2lar` is the inverse function of `lar2cop`. their composition is the identity function.

# Example

```
julia> V,(VV,EV,FV,CV) = Lar.cuboid([1,1,1],true);

julia> Lar.cop2lar(Lar.lar2cop(EV))
12-element Array{Array{Int64,1},1}:
 [1, 2]
 [3, 4]
   ...
 [2, 6]
 [3, 7]
 [4, 8]

julia> Lar.cop2lar(Lar.lar2cop(FV))
6-element Array{Array{Int64,1},1}:
 [1, 2, 3, 4]
 [5, 6, 7, 8]
 [1, 2, 5, 6]
 [3, 4, 7, 8]
 [1, 3, 5, 7]
 [2, 4, 6, 8]

julia> Lar.cop2lar(Lar.lar2cop(CV))
1-element Array{Array{Int64,1},1}:
 [1, 2, 3, 4, 5, 6, 7, 8]
```
"""
function cop2lar(cop::Lar.ChainOp)::Lar.Cells
	[findnz(cop[k,:])[1] for k=1:size(cop,1)]
end


function FV2EVs(copEV::Lar.ChainOp, copFE::Lar.ChainOp)
	EV = [findnz(copEV[k,:])[1] for k=1:size(copEV,1)]
	FE = [findnz(copFE[k,:])[1] for k=1:size(copFE,1)]
	EVs = [[EV[e] for e in fe] for fe in FE]
	return EVs
end


"""
	randomcuboids(n,scale=1.0

Generate the `LAR` model of a collection of `n` random cuboids.
Position, orientation and measure of sides are all random.
"""
function randomcuboids(n,scale=1.0)
	assembly = []
	for k=1:n
		corner = rand(Float64, 2)
		sizes = rand(Float64, 2)
		V,(_,EV,_) = Lar.cuboid(corner,true,corner+sizes)
		center = (corner + corner+sizes)/2
		angle = rand(Float64)*2*pi
		obj = Lar.Struct([ Lar.t(center...), Lar.r(angle), 
				Lar.s(scale,scale), Lar.t(-center...), (V,EV) ])
		push!(assembly, obj)
	end
	Lar.struct2lar(Lar.Struct(assembly))
end



"""
	compute_FV( copEV::Lar.ChainOp, copFE::Lar.ChainOp )::Lar.Cells

Compute the `FV` array of type `Lar.Cells` from two `Lar.ChainOp`, via 
sparse array product.  To be generalized to open 2-manifolds.
"""
function compute_FV( copEV::Lar.ChainOp, copFE::Lar.ChainOp )
	# TODO: generalize for open 2-manifolds
	kFV = (x->div(x,2)).(abs.(copFE) * abs.(copEV)) # works only for closed surfaces
	FV = [SparseArrays.findnz(kFV[k,:])[1] for k=1:size(kFV,1)]
	return FV
end

