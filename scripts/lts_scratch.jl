using LazyGrids
using Plots
using SparseArrays
# using PlotlyJS


Base.@kwdef mutable struct boid{T<:Real}
        position::Vector{T} #2-D to start
        gamma::Vector{T} #Γ_l Γ_r
        angle::T #α
        v::Vector{T} #velocity
        a::Vector{T} #acceleration
end 

Base.@kwdef mutable struct params
    ℓ #dipole length
    Γ₀ #init circulation
    Γₐ #incremental circulation
    v₀ #cruise velocity
    vₐ #incremental velocity
    ρ  #turn radius
    function params(ℓ)
        v0 = 5*ℓ
        g0 = 2π*ℓ*v0 
        ga = 0.1 *g0    
        new(ℓ,g0,ga,v0,v0*0.1,0ℓ)
    end 
end 
    # Print function for a boid
Base.show(io::IO,b::boid) = print(io,"Boid (x,y,α)=($(b.position),$(b.angle)), ̂v = $(b.v)")
   
#SAMPLE constructorS
b = boid([1.0,0.5],[-1.0,1.0], π/2, [0.0,0.0],[0.0,0.0])
sim = params(5e-4)


function vortex_vel(boids::Vector{boid{T}} ;ℓ=0.001) where T<:Real
    """
    find vortex velocity from sources to itself
    sources - vector of vortex_particle type
    DOES NOT UPDATE STATE of sources
    returns velocity induced field
    """  

    n =size(boids)[1]
    vels = zeros(T, (2,n))
    vel = zeros(T, n)
    targets = zeros(T,(2,n))
    for (i,b) in enumerate(boids)
        targets[:,i] = b.position
    end
    # targets = [b.position[:] for b in boids]
    for i in 1:n            
        dx = targets[1,:] .- (boids[i].position[1] .+ ℓ*cos(boids[i].angle+π/2))
        dy = targets[2,:] .- (boids[i].position[2] .+ ℓ*sin(boids[i].angle+π/2))
        @. vel = boids[i].gamma[1]  / (2π *(dx^2 + dy^2 ))
        @. vels[1,:,:] += dy * vel
        @. vels[2,:,:] -= dx * vel
        dx = targets[1,:] .- (boids[i].position[1] .+ ℓ*cos(boids[i].angle-π/2))
        dy = targets[2,:] .- (boids[i].position[2] .+ ℓ*sin(boids[i].angle-π/2))
        @. vel = boids[i].gamma[2] / (2π *(dx^2 + dy^2 ))
        @. vels[1,:,:] += dy * vel
        @. vels[2,:,:] -= dx * vel
    end
    vels
end

function vortex_vel(boids ::Vector{boid{T}}, targets  ;ℓ=0.001) where T<:Real
    """
    find vortex velocity from sources to a LazyGrids of targets
    """

    n = size(boids)[1]
    vels = zeros(T, (2,size(targets[1])...))
    vel = zeros(T, size(targets[1]))
    for i in 1:n            
        #left vortex
        dx = targets[1] .- (boids[i].position[1] .+ ℓ*cos(boids[i].angle+π/2))
        dy = targets[2] .- (boids[i].position[2] .+ ℓ*sin(boids[i].angle+π/2))
        @. vel = boids[i].gamma[1]  / (2π *(dx^2 + dy^2 ))
        @. vels[1,:,:] += dy * vel
        @. vels[2,:,:] -= dx * vel
        #right vortex
        dx = targets[1] .- (boids[i].position[1] .+ ℓ*cos(boids[i].angle-π/2))
        dy = targets[2] .- (boids[i].position[2] .+ ℓ*sin(boids[i].angle-π/2))
        @. vel = boids[i].gamma[2] / (2π *(dx^2 + dy^2 ))
        @. vels[1,:,:] += dy * vel
        @. vels[2,:,:] -= dx * vel
    end
    vels
end


function potential(boids::Vector{boid{T}},targets; ℓ= 0.01) where T<: Real
    """
    find vortex potential from sources to a LazyGrids of targets
    mainly for plotting, but might be worth examining wtih Autodiff
    """
    pot = zeros(T, (size(targets[1])...))

    for b in boids            
        #left vortex
        dx = targets[1] .- (b.position[1] .+ ℓ*cos(b.angle+π/2))
        dy = targets[2] .- (b.position[2] .+ ℓ*sin(b.angle+π/2))
        @. pot += -b.gamma[1] *atan(dx,dy)
        #right vortex
        dx = targets[1] .- (b.position[1] .+ ℓ*cos(b.angle-π/2))
        dy = targets[2] .- (b.position[2] .+ ℓ*sin(b.angle-π/2))
        @. pot += -b.gamma[2] *atan(dx,dy)

        #self influence ? no
        # @show b
        # dx = targets[1] .- b.position[1] 
        # dy = targets[2] .- b.position[2] 
        # @. pot += -(b.gamma[2] - b.gamma[1])/(dx^2 + dy^2)*dy^2
    end
    pot./(2π)
end

function streamfunction(boids::Vector{boid{T}},targets; ℓ= 0.01) where T<: Real
    """
    find vortex streamlines from sources to a LazyGrids of targets
    mainly for plotting, but might be worth examining wtih Autodiff
    """
    pot = zeros(T, (size(targets[1])...))

    for b in boids            
        #left vortex
        dx = targets[1] .- (b.position[1] .+ ℓ*cos(b.angle+π/2))
        dy = targets[2] .- (b.position[2] .+ ℓ*sin(b.angle+π/2))
        @. pot += -b.gamma[1] *log(sqrt(dx^2+dy^2))
        #right vortex
        dx = targets[1] .- (b.position[1] .+ ℓ*cos(b.angle-π/2))
        dy = targets[2] .- (b.position[2] .+ ℓ*sin(b.angle-π/2))
        @. pot += -b.gamma[2] *log(sqrt(dx^2+dy^2))
    
    end
    pot./(2π)
end

function move_swimmers!(boids::Vector{boid{T}}; Δt=0.1, ℓ= 0.01) where T<: Real
    """ Find the velocity induced from each swimmer onto the others and 
        update position via a simple Euler's method """
    ind_v = vortex_vel(boids;ℓ)    
    for (i,b) in enumerate(boids)
        b.v = ind_v[:,i]
        b.position +=  ind_v[:,i] .* Δt
    end
end

#We are using 32-bits throughout
type =T= Base.Float32

# Make a grid - strictly for visualization (so far)
xs = LinRange{type}(-2,2,31)
ys = LinRange{type}(-2,2,21)
targets = ndgrid(xs,ys)
#do it a different way
X = repeat(reshape(xs, 1, :), length(ys), 1)
Y = repeat(ys, 1, length(xs))
targets = [X,Y]


#Velocity induced from swimmer to swimmer
ind_v = vortex_vel(boids)
field_v = vortex_vel(boids, targets;ℓ=0.5)

field_pot = potential(boids, targets;ℓ=0.5)
stream = streamfunction(boids, targets;ℓ=0.5)


#MAKE a few different plotting routines to verify what we would hope to anticipate
clim =  -sim.Γ₀*(xs[2]-xs[1])*(ys[2]-ys[1])
begin 
    #a swimmer going up from origin
    boids = [boid([0.0, 0.0],  [-sim.Γ₀,sim.Γ₀], π/2, [0.0,0.0], [0.0,0.0])]
    field_v = vortex_vel(boids, targets)
    stream = streamfunction(boids, targets)
    clim =  -sim.Γ₀*(xs[2]-xs[1])*(ys[2]-ys[1])
    plot(collect(xs),collect(ys), stream, st=:contourf,clim=(clim,-clim))
    quiver!(targets[1]|>vec,targets[2]|>vec, quiver = (field_v[1,:,:]|>vec,field_v[2,:,:]|>vec),
       xlims=(xs[1],xs[end]),ylims=(ys[1],ys[end]), aspect_ratio= :equal)
    # scatter!([boids[1].position[1]],[boids[1].position[2]],markersize=4,color=:red,label="")
    # scatter!([boids[1].position[1]+ ℓ*cos(boids[1].angle+π/2)],[boids[1].position[2]
    #             + ℓ*sin(boids[1].angle+π/2)], markersize=4,color=:green,label="left")
    # scatter!([boids[1].position[1]+ ℓ*cos(boids[1].angle-π/2)],[boids[1].position[2]
    #             + ℓ*sin(boids[1].angle-π/2)], markersize=4, color=:blue,label="right")
end

begin 
    #a diamond of swimmers going up from origin
    boids = [boid([1.0, 0.0],  [-1.0,1.0], π/2, [0.0,0.0], [0.0,0.0]),
             boid([-1.0, 0.0],  [-1.0,1.0], π/2, [0.0,0.0], [0.0,0.0]),
             boid([0.0, 1.0],  [-1.0,1.0], π/2, [0.0,0.0], [0.0,0.0]),
             boid([0.0, -1.0],  [-1.0,1.0], π/2, [0.0,0.0], [0.0,0.0])]
    field_v = vortex_vel(boids, targets)
    stream = streamfunction(boids, targets)
    plot(collect(xs),collect(ys), stream, st=:contourf)
    quiver!(targets[1]|>vec,targets[2]|>vec, quiver = (field_v[1,:,:]|>vec,field_v[2,:,:]|>vec),
       xlims=(xs[1],xs[end]),ylims=(ys[1],ys[end]),color=:green, aspect_ratio= :equal)
end

begin 
    #swimmers going to the origin
    boids = [boid([1.0, 0.0],  [-1.0,1.0], π/1.0, [0.0,0.0], [0.0,0.0]),
             boid([-1.0, 0.0],  [-1.0,1.0], 0.0, [0.0,0.0], [0.0,0.0]),
             boid([0.0, 1.0],  [-1.0,1.0], -π/2, [0.0,0.0], [0.0,0.0]),
             boid([0.0, -1.0],  [-1.0,1.0], π/2, [0.0,0.0], [0.0,0.0])]
    field_v = vortex_vel(boids, targets)
    stream = streamfunction(boids, targets)
    plot(collect(xs),collect(ys), stream, st=:contourf)
    quiver!(targets[1]|>vec,targets[2]|>vec, quiver = (field_v[1,:,:]|>vec,field_v[2,:,:]|>vec),
       xlims=(xs[1],xs[end]),ylims=(ys[1],ys[end]),color=:green, aspect_ratio= :equal)
end


#The below is busted
begin
    plot(collect(xs),collect(ys), stream, st=:contourf)
    for b in boids
        @show (cos(b.angle),sin(b.angle),b.angle)
        scatter!([b.position[1]],[b.position[2]],markersize=4,color=:red,label="",markershape=:dtriangle)
        # scatter!([b.position[1]+ ℓ*cos(b.angle+π/2)],[b.position[2]+ ℓ*sin(b.angle+π/2)]
        #         ,markersize=4,color=:green,label="left")
        # scatter!([b.position[1]+ ℓ*cos(b.angle-π/2)],[b.position[2]+ ℓ*sin(b.angle-π/2)]
        #         ,markersize=4,color=:blue,label="right")
        # #Why is it only doing quiver in the x-dir?
        # quiver!([b.position[1]], [b.position[2]], quiver= [cos(b.angle),sin(b.angle)])
        
    end
    plot!()
end




boids = []
for i in (-π:π/21 :π)
    # boids = [boid([cos(i), sin(i)],  [-sim.Γ₀,sim.Γ₀],  i, [0.0,0.0], [0.0,0.0])]
    push!(boids, boid([cos(i), sin(i)],  [-sim.Γ₀,sim.Γ₀], -i, [0.0,sim.v₀], [0.0,0.0]))
    # push!(vals,vortex_vel(boids;sim.ℓ)[2])
end
boids = boids|>Vector{boid{Float64}}
Δt =1.0f0
n = 40
anim = @animate for i ∈ 1:n
            move_swimmers!(boids; Δt,sim.ℓ)
            @show boids[1].position[2]
            f_vels = vortex_vel(boids, targets;sim.ℓ)         
            stream = streamfunction(boids, targets;sim.ℓ)
            plot(collect(xs),collect(ys), stream, st=:contourf,clim=(clim,-clim))
            quiver!(targets[1]|>vec,targets[2]|>vec,
                   quiver = (f_vels[1,:,:]|>vec,f_vels[2,:,:]|>vec),
                   aspect_ratio= :equal,
                   xlim=(xs[1],xs[end]),ylim=(ys[1],ys[end]));
            for b in boids        
                scatter!([b.position[1]],[b.position[2]],markersize=4,color=:red,label="",markershape=:utriangle)
            end
            plot
end
gif(anim, "simple_swimmers.gif", fps = 20)
# Define some vortices


quiver([1.0],[2.0],quiver=[0.5,0.5],arrow=true,linewidth=0)
plot([0.0,1.0],[0.0,2.0],marker=(:utriangle,10))
begin
plot()
d=0.1
for b in boids
    # plot!([b.position[1]-d*cos(b.angle)],
    #     [b.position[2]-d*sin(b.angle)],
    #     label="",color=:black,seriestype=:scatter)
    plot!([b.position[1],b.position[1]+d*cos(b.angle)],
          [b.position[2],b.position[2]+d*sin(b.angle)],
          arrow = arrow(:closed),label="",color=:blue,linewidth=.1)
end
plot!()
end