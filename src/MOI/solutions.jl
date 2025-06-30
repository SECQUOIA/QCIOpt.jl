# All Optimizers must implement the following attributes:
# [x] PrimalStatus
function MOI.get(solver::Optimizer{T}, ::MOI.PrimalStatus) where {T}
    if MOI.get(solver, MOI.TerminationStatus()) === MOI.LOCALLY_SOLVED
        return MOI.FEASIBLE_POINT # Since problem is unconstrained, it should always be feasible
    else
        return MOI.NO_SOLUTION
    end
end

# [x] DualStatus
function MOI.get(solver::Optimizer{T}, ::MOI.DualStatus) where {T}
    if MOI.get(solver, MOI.TerminationStatus()) === MOI.LOCALLY_SOLVED
        return MOI.UNKNOWN_RESULT_STATUS # TODO: Figure out what to do with the dual status
    else
        return MOI.NO_SOLUTION
    end
end

# [x] RawStatusString
function MOI.get(solver::Optimizer{T}, ::MOI.RawStatusString) where {T}
    if isempty(solver.solution.metadata)
        return ""
    else
        return solver.solution.metadata["status"]
    end
end

# [x] ResultCount
MOI.get(solver::Optimizer{T}, ::MOI.ResultCount) where {T} = length(solver.solution.samples)

# [x] TerminationStatus
const QCI_TERMINATION_STATUS = Dict{String,Union{MOI.TerminationStatusCode,Nothing}}(
    "CANCELLED" => MOI.INTERRUPTED,
    "COMPLETED" => MOI.LOCALLY_SOLVED,
    "ERRORED"   => MOI.OTHER_ERROR,
    "QUEUED"    => nothing, # Hello darkness, my old friend
    "RUNNING"   => nothing, #
    "SUBMITTED" => nothing, #
)

function MOI.get(solver::Optimizer{T}, ::MOI.TerminationStatus) where {T}
    if isempty(solver.solution.metadata)
        return MOI.OPTIMIZE_NOT_CALLED
    else
        let status = MOI.get(solver, MOI.RawStatusString())
            return QCI_TERMINATION_STATUS[status]
        end
    end
end

# [x] ObjectiveValue
function MOI.get(solver::Optimizer{T}, attr::MOI.ObjectiveValue) where {T}
    @assert 1 <= attr.result_index <= MOI.get(solver, MOI.ResultCount())

    # TODO: Check if this requires any extra adjustments, like evaluating the objective polynomial
    return solver.solution.samples[attr.result_index].value
end

# [ ] SolveTimeSec
function qci_get_elapsed_time(status)
    run_key = only(filter(key -> startswith(key, "running_at_"), keys(status)))
    end_key = only(filter(key -> startswith(key, "completed_at_"), keys(status)))

    run_ts = parse(Dates.DateTime, only(match(r"^(.*)Z$", status[run_key])))
    end_ts = parse(Dates.DateTime, only(match(r"^(.*)Z$", status[end_key])))

    return Dates.seconds(end_ts - run_ts)
end

function MOI.get(solver::Optimizer{T}, ::MOI.SolveTimeSec) where {T}
    # "total elapsed solution time (in seconds) as reported by the optimizer"
    if MOI.get(solver, MOI.TerminationStatus()) === MOI.LOCALLY_SOLVED # means it was completed successfully
        return qci_get_elapsed_time(solver.solution.metadata["job_info"]["job_status"])
    else
        return NaN
    end
end

# [x] VariablePrimal
function MOI.get(solver::Optimizer{T}, attr::MOI.VariablePrimal, vi::VI) where {T}
    @assert 1 <= attr.result_index <= MOI.get(solver, MOI.ResultCount())

    i = var_idx(solver.device.varmap, vi)

    return solver.solution.samples[attr.result_index].point[i]
end

struct ResultMultiplicity <: MOI.AbstractOptimizerAttribute
    result_index::Int

    function ResultMultiplicity(result_index::Integer = 1)
        @assert result_index >= 1
        
        return new(result_index)
    end
end

function MOI.get(solver::Optimizer{T}, attr::ResultMultiplicity) where {T}
    @assert 0 <= attr.result_index <= MOI.get(solver, MOI.ResultCount())

    return solver.solution.samples[attr.result_index].reads
end

MOI.is_set_by_optimize(::ResultMultiplicity) = true
