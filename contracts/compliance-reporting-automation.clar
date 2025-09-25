;; Automated Compliance Reporting System
;; Collect compliance data, generate regulatory reports, and ensure timely submissions

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-unauthorized (err u102))
(define-constant err-invalid-status (err u103))
(define-constant err-insufficient-funds (err u104))
(define-constant err-invalid-data (err u105))
(define-constant err-report-exists (err u106))
(define-constant err-deadline-passed (err u107))
(define-constant err-invalid-period (err u108))
(define-constant err-submission-failed (err u109))

;; Report Status Constants
(define-constant status-draft u0)
(define-constant status-pending u1)
(define-constant status-approved u2)
(define-constant status-submitted u3)
(define-constant status-rejected u4)
(define-constant status-overdue u5)

;; Compliance Type Constants
(define-constant type-aml u0)
(define-constant type-kyc u1)
(define-constant type-financial u2)
(define-constant type-risk u3)
(define-constant type-privacy u4)
(define-constant type-operational u5)

;; Priority Levels
(define-constant priority-low u0)
(define-constant priority-medium u1)
(define-constant priority-high u2)
(define-constant priority-critical u3)

;; Time Constants
(define-constant blocks-per-day u144)
(define-constant blocks-per-week u1008)
(define-constant blocks-per-month u4320)
(define-constant default-deadline-extension u720) ;; 5 days

;; Data Variables
(define-data-var report-counter uint u0)
(define-data-var total-submissions uint u0)
(define-data-var contract-paused bool false)
(define-data-var default-review-period uint u288) ;; 2 days
(define-data-var late-submission-penalty uint u100000) ;; 0.1 STX

;; Data Maps
(define-map compliance-reports
  uint
  {
    report-id: uint,
    entity-id: (string-ascii 64),
    report-type: uint,
    period-start: uint,
    period-end: uint,
    created-by: principal,
    created-at: uint,
    deadline: uint,
    status: uint,
    priority: uint,
    data-hash: (buff 32),
    submission-hash: (optional (buff 32)),
    approved-by: (optional principal),
    approved-at: (optional uint),
    submitted-at: (optional uint),
    notes: (string-ascii 256)
  }
)

(define-map compliance-entities
  (string-ascii 64)
  {
    name: (string-ascii 128),
    regulator: (string-ascii 64),
    jurisdiction: (string-ascii 32),
    entity-type: (string-ascii 32),
    registration-number: (string-ascii 64),
    contact-email: (string-ascii 128),
    is-active: bool,
    created-at: uint,
    last-updated: uint
  }
)

(define-map compliance-officers
  principal
  {
    name: (string-ascii 64),
    role: (string-ascii 32),
    permissions: (list 10 (string-ascii 20)),
    entity-ids: (list 20 (string-ascii 64)),
    is-active: bool,
    created-at: uint,
    last-login: (optional uint)
  }
)

(define-map regulatory-requirements
  {entity-type: (string-ascii 32), report-type: uint}
  {
    frequency: uint, ;; in blocks
    deadline-days: uint,
    required-fields: (list 20 (string-ascii 32)),
    validation-rules: (string-ascii 256),
    regulator: (string-ascii 64),
    is-mandatory: bool
  }
)

(define-map data-collections
  {report-id: uint, data-point: (string-ascii 32)}
  {
    value: (string-ascii 256),
    data-type: (string-ascii 16),
    collected-at: uint,
    source: (string-ascii 64),
    verified: bool,
    verifier: (optional principal)
  }
)

(define-map audit-trail
  uint
  {
    report-id: uint,
    action: (string-ascii 32),
    performed-by: principal,
    timestamp: uint,
    details: (string-ascii 256),
    previous-status: (optional uint),
    new-status: (optional uint)
  }
)

(define-map submission-history
  uint
  {
    report-id: uint,
    submission-id: (string-ascii 64),
    submitted-to: (string-ascii 64),
    submission-method: (string-ascii 32),
    submitted-at: uint,
    acknowledgment: (optional (string-ascii 128)),
    status: (string-ascii 16),
    retry-count: uint
  }
)

;; Private Functions

(define-private (is-contract-owner (user principal))
  (is-eq user contract-owner)
)

(define-private (is-compliance-officer (user principal))
  (is-some (map-get? compliance-officers user))
)

(define-private (has-entity-access (officer principal) (entity-id (string-ascii 64)))
  (match (map-get? compliance-officers officer)
    officer-data
    (is-some (index-of (get entity-ids officer-data) entity-id))
    false
  )
)

(define-private (calculate-deadline (report-type uint) (period-end uint) (entity-type (string-ascii 32)))
  (match (map-get? regulatory-requirements {entity-type: entity-type, report-type: report-type})
    req-data
    (+ period-end (* (get deadline-days req-data) blocks-per-day))
    (+ period-end (* u30 blocks-per-day)) ;; default 30 days
  )
)

(define-private (is-overdue (deadline uint))
  (> block-height deadline)
)

(define-private (get-next-report-id)
  (let (
    (current-counter (var-get report-counter))
    (next-id (+ current-counter u1))
  )
    (var-set report-counter next-id)
    next-id
  )
)

(define-private (log-audit-event (report-id uint) (action (string-ascii 32)) (details (string-ascii 256)) (prev-status (optional uint)) (new-status (optional uint)))
  (let (
    (audit-id (+ (var-get report-counter) u1000000)) ;; offset for audit IDs
  )
    (map-set audit-trail audit-id {
      report-id: report-id,
      action: action,
      performed-by: tx-sender,
      timestamp: block-height,
      details: details,
      previous-status: prev-status,
      new-status: new-status
    })
  )
)

;; Read-Only Functions

(define-read-only (get-compliance-report (report-id uint))
  (ok (map-get? compliance-reports report-id))
)

(define-read-only (get-compliance-entity (entity-id (string-ascii 64)))
  (ok (map-get? compliance-entities entity-id))
)

(define-read-only (get-compliance-officer (officer principal))
  (ok (map-get? compliance-officers officer))
)

(define-read-only (get-regulatory-requirement (entity-type (string-ascii 32)) (report-type uint))
  (ok (map-get? regulatory-requirements {entity-type: entity-type, report-type: report-type}))
)

(define-read-only (get-data-collection (report-id uint) (data-point (string-ascii 32)))
  (ok (map-get? data-collections {report-id: report-id, data-point: data-point}))
)

(define-read-only (get-audit-trail (audit-id uint))
  (ok (map-get? audit-trail audit-id))
)

(define-read-only (get-submission-history (submission-id uint))
  (ok (map-get? submission-history submission-id))
)

(define-read-only (get-overdue-reports)
  (ok {
    current-block: block-height,
    check-deadline: "Use individual report checks"
  })
)

(define-read-only (get-contract-stats)
  (ok {
    total-reports: (var-get report-counter),
    total-submissions: (var-get total-submissions),
    contract-paused: (var-get contract-paused),
    default-review-period: (var-get default-review-period)
  })
)

;; Public Functions

(define-public (register-compliance-entity 
  (entity-id (string-ascii 64))
  (name (string-ascii 128))
  (regulator (string-ascii 64))
  (jurisdiction (string-ascii 32))
  (entity-type (string-ascii 32))
  (registration-number (string-ascii 64))
  (contact-email (string-ascii 128))
)
  (begin
    (asserts! (is-contract-owner tx-sender) err-owner-only)
    (asserts! (is-none (map-get? compliance-entities entity-id)) err-report-exists)
    
    (map-set compliance-entities entity-id {
      name: name,
      regulator: regulator,
      jurisdiction: jurisdiction,
      entity-type: entity-type,
      registration-number: registration-number,
      contact-email: contact-email,
      is-active: true,
      created-at: block-height,
      last-updated: block-height
    })
    
    (ok entity-id)
  )
)

(define-public (register-compliance-officer
  (officer principal)
  (name (string-ascii 64))
  (role (string-ascii 32))
  (permissions (list 10 (string-ascii 20)))
  (entity-ids (list 20 (string-ascii 64)))
)
  (begin
    (asserts! (is-contract-owner tx-sender) err-owner-only)
    
    (map-set compliance-officers officer {
      name: name,
      role: role,
      permissions: permissions,
      entity-ids: entity-ids,
      is-active: true,
      created-at: block-height,
      last-login: none
    })
    
    (ok officer)
  )
)

(define-public (create-compliance-report
  (entity-id (string-ascii 64))
  (report-type uint)
  (period-start uint)
  (period-end uint)
  (priority uint)
  (data-hash (buff 32))
  (notes (string-ascii 256))
)
  (let (
    (report-id (get-next-report-id))
    (entity-data (unwrap! (map-get? compliance-entities entity-id) err-not-found))
    (deadline (calculate-deadline report-type period-end (get entity-type entity-data)))
  )
    (asserts! (is-compliance-officer tx-sender) err-unauthorized)
    (asserts! (has-entity-access tx-sender entity-id) err-unauthorized)
    (asserts! (not (var-get contract-paused)) (err u110))
    (asserts! (> period-end period-start) err-invalid-period)
    
    (map-set compliance-reports report-id {
      report-id: report-id,
      entity-id: entity-id,
      report-type: report-type,
      period-start: period-start,
      period-end: period-end,
      created-by: tx-sender,
      created-at: block-height,
      deadline: deadline,
      status: status-draft,
      priority: priority,
      data-hash: data-hash,
      submission-hash: none,
      approved-by: none,
      approved-at: none,
      submitted-at: none,
      notes: notes
    })
    
    (log-audit-event report-id "created" notes none (some status-draft))
    
    (ok report-id)
  )
)

(define-public (collect-data-point
  (report-id uint)
  (data-point (string-ascii 32))
  (value (string-ascii 256))
  (data-type (string-ascii 16))
  (source (string-ascii 64))
)
  (let (
    (report-data (unwrap! (map-get? compliance-reports report-id) err-not-found))
  )
    (asserts! (is-compliance-officer tx-sender) err-unauthorized)
    (asserts! (has-entity-access tx-sender (get entity-id report-data)) err-unauthorized)
    (asserts! (or (is-eq (get status report-data) status-draft)
                  (is-eq (get status report-data) status-pending)) err-invalid-status)
    
    (map-set data-collections 
      {report-id: report-id, data-point: data-point}
      {
        value: value,
        data-type: data-type,
        collected-at: block-height,
        source: source,
        verified: false,
        verifier: none
      }
    )
    
    (log-audit-event report-id "data-collected" data-point none none)
    
    (ok true)
  )
)

(define-public (verify-data-point
  (report-id uint)
  (data-point (string-ascii 32))
)
  (let (
    (report-data (unwrap! (map-get? compliance-reports report-id) err-not-found))
    (data-record (unwrap! (map-get? data-collections {report-id: report-id, data-point: data-point}) err-not-found))
  )
    (asserts! (is-compliance-officer tx-sender) err-unauthorized)
    (asserts! (has-entity-access tx-sender (get entity-id report-data)) err-unauthorized)
    
    (map-set data-collections 
      {report-id: report-id, data-point: data-point}
      (merge data-record {
        verified: true,
        verifier: (some tx-sender)
      })
    )
    
    (log-audit-event report-id "data-verified" data-point none none)
    
    (ok true)
  )
)

(define-public (submit-for-review (report-id uint))
  (let (
    (report-data (unwrap! (map-get? compliance-reports report-id) err-not-found))
  )
    (asserts! (is-compliance-officer tx-sender) err-unauthorized)
    (asserts! (has-entity-access tx-sender (get entity-id report-data)) err-unauthorized)
    (asserts! (is-eq (get status report-data) status-draft) err-invalid-status)
    
    (map-set compliance-reports report-id 
      (merge report-data {
        status: status-pending
      })
    )
    
    (log-audit-event report-id "submitted-review" "Report submitted for review" 
                     (some status-draft) (some status-pending))
    
    (ok true)
  )
)

(define-public (approve-report (report-id uint) (approval-notes (string-ascii 256)))
  (let (
    (report-data (unwrap! (map-get? compliance-reports report-id) err-not-found))
  )
    (asserts! (is-compliance-officer tx-sender) err-unauthorized)
    (asserts! (has-entity-access tx-sender (get entity-id report-data)) err-unauthorized)
    (asserts! (is-eq (get status report-data) status-pending) err-invalid-status)
    
    (map-set compliance-reports report-id 
      (merge report-data {
        status: status-approved,
        approved-by: (some tx-sender),
        approved-at: (some block-height),
        notes: approval-notes
      })
    )
    
    (log-audit-event report-id "approved" approval-notes 
                     (some status-pending) (some status-approved))
    
    (ok true)
  )
)

(define-public (submit-report 
  (report-id uint) 
  (submission-id (string-ascii 64))
  (regulator (string-ascii 64))
  (submission-method (string-ascii 32))
  (submission-hash (buff 32))
)
  (let (
    (report-data (unwrap! (map-get? compliance-reports report-id) err-not-found))
    (submission-record-id (+ report-id u2000000)) ;; offset for submission IDs
  )
    (asserts! (is-compliance-officer tx-sender) err-unauthorized)
    (asserts! (has-entity-access tx-sender (get entity-id report-data)) err-unauthorized)
    (asserts! (is-eq (get status report-data) status-approved) err-invalid-status)
    
    ;; Check if deadline has passed and apply penalty if necessary
    (if (is-overdue (get deadline report-data))
      (try! (stx-transfer? (var-get late-submission-penalty) tx-sender (as-contract tx-sender)))
      true
    )
    
    (map-set compliance-reports report-id 
      (merge report-data {
        status: status-submitted,
        submission-hash: (some submission-hash),
        submitted-at: (some block-height)
      })
    )
    
    (map-set submission-history submission-record-id {
      report-id: report-id,
      submission-id: submission-id,
      submitted-to: regulator,
      submission-method: submission-method,
      submitted-at: block-height,
      acknowledgment: none,
      status: "submitted",
      retry-count: u0
    })
    
    (var-set total-submissions (+ (var-get total-submissions) u1))
    
    (log-audit-event report-id "submitted" "Report submitted to regulator" 
                     (some status-approved) (some status-submitted))
    
    (ok submission-record-id)
  )
)

(define-public (update-submission-status
  (submission-record-id uint)
  (acknowledgment (string-ascii 128))
  (status (string-ascii 16))
)
  (let (
    (submission-data (unwrap! (map-get? submission-history submission-record-id) err-not-found))
  )
    (asserts! (is-compliance-officer tx-sender) err-unauthorized)
    
    (map-set submission-history submission-record-id 
      (merge submission-data {
        acknowledgment: (some acknowledgment),
        status: status
      })
    )
    
    (log-audit-event (get report-id submission-data) "status-updated" acknowledgment none none)
    
    (ok true)
  )
)

;; Admin Functions

(define-public (pause-contract)
  (begin
    (asserts! (is-contract-owner tx-sender) err-owner-only)
    (var-set contract-paused true)
    (ok true)
  )
)

(define-public (unpause-contract)
  (begin
    (asserts! (is-contract-owner tx-sender) err-owner-only)
    (var-set contract-paused false)
    (ok true)
  )
)

(define-public (set-regulatory-requirement
  (entity-type (string-ascii 32))
  (report-type uint)
  (frequency uint)
  (deadline-days uint)
  (required-fields (list 20 (string-ascii 32)))
  (validation-rules (string-ascii 256))
  (regulator (string-ascii 64))
  (is-mandatory bool)
)
  (begin
    (asserts! (is-contract-owner tx-sender) err-owner-only)
    
    (map-set regulatory-requirements 
      {entity-type: entity-type, report-type: report-type}
      {
        frequency: frequency,
        deadline-days: deadline-days,
        required-fields: required-fields,
        validation-rules: validation-rules,
        regulator: regulator,
        is-mandatory: is-mandatory
      }
    )
    
    (ok true)
  )
)

(define-public (update-penalty-amount (new-penalty uint))
  (begin
    (asserts! (is-contract-owner tx-sender) err-owner-only)
    (var-set late-submission-penalty new-penalty)
    (ok true)
  )
)
