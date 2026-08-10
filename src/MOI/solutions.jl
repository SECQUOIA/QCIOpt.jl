# All Optimizers must implement the following attributes:
# [x] PrimalStatus
# The devices are unconstrained samplers, so every returned sample is a feasible
# point. Out-of-bounds result indices report `MOI.NO_SOLUTION`, following the
# MathOptInterface convention for `PrimalStatus`.
function MOI.get(solver::Optimizer{T}, attr::MOI.PrimalStatus) where {T}
    if 1 <= attr.result_index <= MOI.get(solver, MOI.ResultCount())
        return MOI.FEASIBLE_POINT
    else
        return MOI.NO_SOLUTION
    end
end

# [x] DualStatus
# QCI devices are sampler backends for unconstrained models: no dual problem is
# formulated and no dual values are ever computed, so the dual status is always
# `MOI.NO_SOLUTION` regardless of the result index or termination status.
MOI.get(::Optimizer{T}, ::MOI.DualStatus) where {T} = MOI.NO_SOLUTION

# [x] RawStatusString
function MOI.get(solver::Optimizer{T}, ::MOI.RawStatusString) where {T}
    if isempty(solver.solution.metadata)
        return "OPTIMIZE_NOT_CALLED"
    else
        return solver.solution.metadata["status"]
    end
end

# [x] ResultCount
MOI.get(solver::Optimizer{T}, ::MOI.ResultCount) where {T} = length(solver.solution.samples)

# [x] TerminationStatus
@doc raw"""
    QCI_TERMINATION_STATUS

Mapping from the QCI provider job status to `MOI.TerminationStatusCode`:

| Provider status | MOI status           | Meaning                                             |
|:----------------|:---------------------|:----------------------------------------------------|
| `"COMPLETED"`   | `MOI.LOCALLY_SOLVED` | The sampler returned solutions (heuristic, no bound) |
| `"CANCELLED"`   | `MOI.INTERRUPTED`    | The job was cancelled before completion              |
| `"ERRORED"`     | `MOI.OTHER_ERROR`    | The provider reported a job error                    |
| `"QUEUED"`      | `MOI.OTHER_LIMIT`    | The solve ended while the job was still queued       |
| `"RUNNING"`     | `MOI.OTHER_LIMIT`    | The solve ended while the job was still running      |
| `"SUBMITTED"`   | `MOI.OTHER_LIMIT`    | The solve ended right after submission               |

The `QUEUED`/`RUNNING`/`SUBMITTED` states are non-terminal on the provider side:
the blocking client normally waits for a terminal state, so observing one of
them means the solve stopped before the provider finished. They map to
`MOI.OTHER_LIMIT` (a non-error early stop) with no results; the exact provider
state remains available through `MOI.RawStatusString`. Unrecognized status
strings map to `MOI.OTHER_ERROR`.
"""
const QCI_TERMINATION_STATUS = Dict{String,MOI.TerminationStatusCode}(
    "CANCELLED" => MOI.INTERRUPTED,
    "COMPLETED" => MOI.LOCALLY_SOLVED,
    "ERRORED"   => MOI.OTHER_ERROR,
    "QUEUED"    => MOI.OTHER_LIMIT,
    "RUNNING"   => MOI.OTHER_LIMIT,
    "SUBMITTED" => MOI.OTHER_LIMIT,
)

function MOI.get(solver::Optimizer{T}, ::MOI.TerminationStatus) where {T}
    if isempty(solver.solution.metadata)
        return MOI.OPTIMIZE_NOT_CALLED
    else
        let status = MOI.get(solver, MOI.RawStatusString())
            return get(QCI_TERMINATION_STATUS, status, MOI.OTHER_ERROR)
        end
    end
end

# [x] ObjectiveValue
# Objective values are recomputed locally by the device layer when results are
# parsed (`readjust_qubo_values` / `readjust_poly_values`): each sample's value
# is the original model objective evaluated at the returned point, including
# constant offsets and, for maximization, the sign flip that undoes the
# negation applied at submission. Invalid result indices throw
# `MOI.ResultIndexBoundsError`.
function MOI.get(solver::Optimizer{T}, attr::MOI.ObjectiveValue) where {T}
    MOI.check_result_index_bounds(solver, attr)

    return solver.solution.samples[attr.result_index].value
end

# [ ] SolveTimeSec
function qci_get_elapsed_time(status)
    run_key = only(filter(key -> startswith(key, "running_at_"), keys(status)))
    end_key = only(filter(key -> startswith(key, "completed_at_"), keys(status)))

    run_ts = parse(Dates.DateTime, only(match(r"^(.*)Z$", status[run_key])))
    end_ts = parse(Dates.DateTime, only(match(r"^(.*)Z$", status[end_key])))

    return Dates.value(end_ts - run_ts) / 1000
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
    MOI.check_result_index_bounds(solver, attr)

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
    MOI.check_result_index_bounds(solver, attr)

    return solver.solution.samples[attr.result_index].reads
end

MOI.is_set_by_optimize(::ResultMultiplicity) = true
