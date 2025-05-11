# All Optimizers must implement the following attributes:
# [ ] DualStatus
# [ ] PrimalStatus
# [ ] RawStatusString
# TODO: Get JobStatus! Possible QCI job statuses are: 'CANCELLED', 'COMPLETED', 'ERRORED', 'QUEUED', 'RUNNING', 'SUBMITTED'

# [x] ResultCount
MOI.get(solver::Optimizer{T}, ::MOI.ResultCount) where {T} = length(solver.samples)

# [ ] TerminationStatus
# TODO: Translate RawStatusString into a TerminationStatus

# [x] ObjectiveValue
function MOI.get(solver::Optimizer{T}, attr::MOI.ObjectiveValue) where {T}
    @assert 0 <= attr.result_index <= MOI.get(solver, MOI.ResultCount())

    # TODO: Check if this requires any extra adjustments, like evaluating the objective polynomial
    return solver.samples[attr.result_index].v
end

# [ ] SolveTimeSec

# [x] VariablePrimal
function MOI.get(solver::Optimizer{T}, attr::MOI.VariablePrimal, vi::VI) where {T}
    @assert 0 <= attr.result_index <= MOI.get(solver, MOI.ResultCount())

    xi = var_map(solver.source_map, vi)
    yi = var_map(solver.target_map, xi)

    return solver.samples[attr.result_index].x[yi]
end
