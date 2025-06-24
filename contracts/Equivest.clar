;; title: Equivest
;; version: 1.0.0
;; summary: Startup Equity Vesting Smart Contract with Milestone-Based Token Unlocking
;; description: A smart contract for managing startup equity vesting with milestone-based token releases

(define-fungible-token equity-token)

(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_INVALID_AMOUNT (err u101))
(define-constant ERR_INSUFFICIENT_BALANCE (err u102))
(define-constant ERR_VESTING_NOT_FOUND (err u103))
(define-constant ERR_MILESTONE_NOT_FOUND (err u104))
(define-constant ERR_MILESTONE_ALREADY_COMPLETED (err u105))
(define-constant ERR_INVALID_RECIPIENT (err u106))
(define-constant ERR_VESTING_ALREADY_EXISTS (err u107))

(define-data-var total-supply uint u0)
(define-data-var milestone-counter uint u0)

(define-map vesting-schedules
  { recipient: principal }
  {
    total-amount: uint,
    vested-amount: uint,
    cliff-height: uint,
    created-at: uint,
    is-active: bool
  }
)

(define-map milestones
  { milestone-id: uint }
  {
    recipient: principal,
    amount: uint,
    description: (string-ascii 100),
    target-block: uint,
    is-completed: bool,
    completed-at: (optional uint)
  }
)

(define-map recipient-milestones
  { recipient: principal, milestone-id: uint }
  { exists: bool }
)

(define-public (mint-tokens (amount uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (try! (ft-mint? equity-token amount tx-sender))
    (var-set total-supply (+ (var-get total-supply) amount))
    (ok amount)
  )
)

(define-public (create-vesting-schedule 
  (recipient principal) 
  (total-amount uint) 
  (cliff-blocks uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (> total-amount u0) ERR_INVALID_AMOUNT)
    (asserts! (not (is-eq recipient CONTRACT_OWNER)) ERR_INVALID_RECIPIENT)
    (asserts! (is-none (map-get? vesting-schedules { recipient: recipient })) ERR_VESTING_ALREADY_EXISTS)
    
    (map-set vesting-schedules
      { recipient: recipient }
      {
        total-amount: total-amount,
        vested-amount: u0,
        cliff-height: (+ stacks-block-height cliff-blocks),
        created-at: stacks-block-height,
        is-active: true
      }
    )
    (ok true)
  )
)

(define-public (add-milestone 
  (recipient principal) 
  (amount uint) 
  (description (string-ascii 100)) 
  (blocks-from-now uint))
  (let
    (
      (milestone-id (+ (var-get milestone-counter) u1))
      (target-block (+ stacks-block-height blocks-from-now))
    )
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (asserts! (is-some (map-get? vesting-schedules { recipient: recipient })) ERR_VESTING_NOT_FOUND)
    
    (map-set milestones
      { milestone-id: milestone-id }
      {
        recipient: recipient,
        amount: amount,
        description: description,
        target-block: target-block,
        is-completed: false,
        completed-at: none
      }
    )
    
    (map-set recipient-milestones
      { recipient: recipient, milestone-id: milestone-id }
      { exists: true }
    )
    
    (var-set milestone-counter milestone-id)
    (ok milestone-id)
  )
)

(define-public (complete-milestone (milestone-id uint))
  (let
    (
      (milestone (unwrap! (map-get? milestones { milestone-id: milestone-id }) ERR_MILESTONE_NOT_FOUND))
      (recipient (get recipient milestone))
      (amount (get amount milestone))
      (vesting-schedule (unwrap! (map-get? vesting-schedules { recipient: recipient }) ERR_VESTING_NOT_FOUND))
    )
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (not (get is-completed milestone)) ERR_MILESTONE_ALREADY_COMPLETED)
    (asserts! (>= stacks-block-height (get target-block milestone)) ERR_UNAUTHORIZED)
    (asserts! (get is-active vesting-schedule) ERR_VESTING_NOT_FOUND)
    
    (map-set milestones
      { milestone-id: milestone-id }
      (merge milestone {
        is-completed: true,
        completed-at: (some stacks-block-height)
      })
    )
    
    (map-set vesting-schedules
      { recipient: recipient }
      (merge vesting-schedule {
        vested-amount: (+ (get vested-amount vesting-schedule) amount)
      })
    )
    
    (try! (ft-transfer? equity-token amount tx-sender recipient))
    (ok amount)
  )
)

(define-public (claim-vested-tokens)
  (let
    (
      (vesting-schedule (unwrap! (map-get? vesting-schedules { recipient: tx-sender }) ERR_VESTING_NOT_FOUND))
      (claimable-amount (get-claimable-amount tx-sender))
    )
    (asserts! (> claimable-amount u0) ERR_INSUFFICIENT_BALANCE)
    (asserts! (get is-active vesting-schedule) ERR_VESTING_NOT_FOUND)
    (asserts! (>= stacks-block-height (get cliff-height vesting-schedule)) ERR_UNAUTHORIZED)
    
    (try! (ft-transfer? equity-token claimable-amount CONTRACT_OWNER tx-sender))
    (ok claimable-amount)
  )
)

(define-public (revoke-vesting (recipient principal))
  (let
    (
      (vesting-schedule (unwrap! (map-get? vesting-schedules { recipient: recipient }) ERR_VESTING_NOT_FOUND))
    )
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (get is-active vesting-schedule) ERR_VESTING_NOT_FOUND)
    
    (map-set vesting-schedules
      { recipient: recipient }
      (merge vesting-schedule { is-active: false })
    )
    (ok true)
  )
)

(define-read-only (get-vesting-schedule (recipient principal))
  (map-get? vesting-schedules { recipient: recipient })
)

(define-read-only (get-milestone (milestone-id uint))
  (map-get? milestones { milestone-id: milestone-id })
)

(define-read-only (get-token-balance (account principal))
  (ft-get-balance equity-token account)
)

(define-read-only (get-total-supply)
  (var-get total-supply)
)

(define-read-only (get-claimable-amount (recipient principal))
  (match (map-get? vesting-schedules { recipient: recipient })
    vesting-schedule
    (if (and 
          (get is-active vesting-schedule)
          (>= stacks-block-height (get cliff-height vesting-schedule)))
      (get vested-amount vesting-schedule)
      u0)
    u0
  )
)

(define-read-only (get-vesting-progress (recipient principal))
  (match (map-get? vesting-schedules { recipient: recipient })
    vesting-schedule
    {
      total-amount: (get total-amount vesting-schedule),
      vested-amount: (get vested-amount vesting-schedule),
      claimable-amount: (get-claimable-amount recipient),
      cliff-height: (get cliff-height vesting-schedule),
      current-block: stacks-block-height,
      is-active: (get is-active vesting-schedule)
    }
    {
      total-amount: u0,
      vested-amount: u0,
      claimable-amount: u0,
      cliff-height: u0,
      current-block: stacks-block-height,
      is-active: false
    }
  )
)

(define-read-only (is-milestone-eligible (milestone-id uint))
  (match (map-get? milestones { milestone-id: milestone-id })
    milestone
    (and 
      (not (get is-completed milestone))
      (>= stacks-block-height (get target-block milestone)))
    false
  )
)

(define-read-only (get-milestone-counter)
  (var-get milestone-counter)
)