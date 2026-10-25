///|
/// Keep derived trait methods explicit for newer MoonBit toolchains.
pub extend ModelError with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ModelError with Eq::{not_equal, equal}

///|
pub extend ResourceId with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ResourceId with Eq::{not_equal, equal}

///|
pub extend ResourceSpec with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ResourceSpec with Eq::{not_equal, equal}

///|
pub extend DesiredState with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend DesiredState with Eq::{not_equal, equal}

///|
pub extend ObservedState with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ObservedState with Eq::{not_equal, equal}

///|
pub extend ActionKind with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ActionKind with Eq::{not_equal, equal}

///|
pub extend Operation with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend Operation with Eq::{not_equal, equal}

///|
pub extend PlanId with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend PlanId with Eq::{not_equal, equal}

///|
pub extend ApprovalState with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ApprovalState with Eq::{not_equal, equal}

///|
pub extend Plan with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend Plan with Eq::{not_equal, equal}

///|
pub extend ExecutionState with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ExecutionState with Eq::{not_equal, equal}

///|
pub extend ExecutionResult with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ExecutionResult with Eq::{not_equal, equal}

///|
pub extend DiffResult with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend DiffResult with Eq::{not_equal, equal}

///|
pub extend ChangeBudget with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ChangeBudget with Eq::{not_equal, equal}

///|
pub extend ChangeBatch with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ChangeBatch with Eq::{not_equal, equal}

///|
pub extend BatchedPlan with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend BatchedPlan with Eq::{not_equal, equal}

///|
pub extend RiskLevel with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend RiskLevel with Eq::{not_equal, equal}

///|
pub extend PolicyDecision with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend PolicyDecision with Eq::{not_equal, equal}

///|
pub extend PolicyReasonCode with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend PolicyReasonCode with Eq::{not_equal, equal}

///|
pub extend PolicyEvaluation with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend PolicyEvaluation with Eq::{not_equal, equal}

///|
pub extend SafetyPolicy with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend SafetyPolicy with Eq::{not_equal, equal}

///|
pub extend AuditEventKind with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend AuditEventKind with Eq::{not_equal, equal}

///|
pub extend AuditReasonCode with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend AuditReasonCode with Eq::{not_equal, equal}

///|
pub extend AuditOperation with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend AuditOperation with Eq::{not_equal, equal}

///|
pub extend AuditEvent with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend AuditEvent with Eq::{not_equal, equal}

///|
pub extend ReconciliationState with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ReconciliationState with Eq::{not_equal, equal}

///|
pub extend Reconciliation with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend Reconciliation with Eq::{not_equal, equal}

///|
pub extend ObservationSnapshot with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ObservationSnapshot with Eq::{not_equal, equal}

///|
pub extend ValidationStatus with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ValidationStatus with Eq::{not_equal, equal}

///|
pub extend ValidationCode with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ValidationCode with Eq::{not_equal, equal}

///|
pub extend ValidationIssue with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ValidationIssue with Eq::{not_equal, equal}

///|
pub extend ValidationResult with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ValidationResult with Eq::{not_equal, equal}

///|
pub extend PlanValidationInput with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend PlanValidationInput with Eq::{not_equal, equal}
