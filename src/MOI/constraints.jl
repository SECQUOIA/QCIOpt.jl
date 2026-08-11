function qci_supports_constraint end

qci_supports_constraint(::QCI_DEVICE, ::Type{F}, ::Type{S}) where {F,S} = false

function MOI.supports_constraint(
    solver::Optimizer,
    function_type::Type{F},
    set_type::Type{S},
) where {F<:MOI.AbstractFunction,S<:MOI.AbstractSet}
    return qci_supports_constraint(solver.device, function_type, set_type)
end
