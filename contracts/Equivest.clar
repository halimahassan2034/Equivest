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
(define-constant ERR_ORDER_NOT_FOUND (err u108))
(define-constant ERR_INVALID_PRICE (err u109))
(define-constant ERR_ORDER_ALREADY_FILLED (err u110))
(define-constant ERR_INSUFFICIENT_TOKENS (err u111))
(define-constant ERR_CANNOT_FILL_OWN_ORDER (err u112))
(define-constant ERR_ORDER_EXPIRED (err u113))
(define-constant ERR_DELEGATION_NOT_FOUND (err u114))
(define-constant ERR_DELEGATION_LOOP (err u115))
(define-constant ERR_DELEGATION_EXPIRED (err u116))
(define-constant ERR_INVALID_DELEGATION_TYPE (err u117))
(define-constant ERR_DELEGATION_ALREADY_EXISTS (err u118))
(define-constant ERR_CANNOT_DELEGATE_TO_SELF (err u119))

(define-data-var total-supply uint u0)
(define-data-var milestone-counter uint u0)
(define-data-var order-counter uint u0)
(define-data-var delegation-counter uint u0)

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

(define-map trading-orders
  { order-id: uint }
  {
    seller: principal,
    amount: uint,
    price-per-token: uint,
    expires-at: uint,
    is-filled: bool,
    filled-at: (optional uint),
    buyer: (optional principal)
  }
)

(define-map user-orders
  { user: principal, order-id: uint }
  { exists: bool }
)

(define-map delegations
  { delegator: principal, delegation-type: uint }
  {
    delegate: principal,
    created-at: uint,
    expires-at: uint,
    is-active: bool,
    delegation-id: uint
  }
)

(define-map delegation-registry
  { delegation-id: uint }
  {
    delegator: principal,
    delegate: principal,
    delegation-type: uint,
    voting-power: uint,
    created-at: uint,
    expires-at: uint,
    is-active: bool
  }
)

(define-map delegate-powers
  { delegate: principal, delegation-type: uint }
  {
    total-voting-power: uint,
    active-delegations: uint
  }
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

(define-public (create-sell-order (amount uint) (price-per-token uint) (blocks-until-expiry uint))
  (let
    (
      (order-id (+ (var-get order-counter) u1))
      (expires-at (+ stacks-block-height blocks-until-expiry))
      (seller-balance (ft-get-balance equity-token tx-sender))
    )
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (asserts! (> price-per-token u0) ERR_INVALID_PRICE)
    (asserts! (> blocks-until-expiry u0) ERR_INVALID_AMOUNT)
    (asserts! (>= seller-balance amount) ERR_INSUFFICIENT_TOKENS)
    
    (try! (ft-transfer? equity-token amount tx-sender (as-contract tx-sender)))
    
    (map-set trading-orders
      { order-id: order-id }
      {
        seller: tx-sender,
        amount: amount,
        price-per-token: price-per-token,
        expires-at: expires-at,
        is-filled: false,
        filled-at: none,
        buyer: none
      }
    )
    
    (map-set user-orders
      { user: tx-sender, order-id: order-id }
      { exists: true }
    )
    
    (var-set order-counter order-id)
    (ok order-id)
  )
)

(define-public (fill-order (order-id uint))
  (let
    (
      (order (unwrap! (map-get? trading-orders { order-id: order-id }) ERR_ORDER_NOT_FOUND))
      (seller (get seller order))
      (amount (get amount order))
      (price-per-token (get price-per-token order))
      (total-cost (* amount price-per-token))
      (expires-at (get expires-at order))
      (is-filled (get is-filled order))
      (buyer-balance (ft-get-balance equity-token tx-sender))
    )
    (asserts! (not is-filled) ERR_ORDER_ALREADY_FILLED)
    (asserts! (< stacks-block-height expires-at) ERR_ORDER_EXPIRED)
    (asserts! (not (is-eq tx-sender seller)) ERR_CANNOT_FILL_OWN_ORDER)
    (asserts! (>= buyer-balance total-cost) ERR_INSUFFICIENT_TOKENS)
    
    (try! (ft-transfer? equity-token total-cost tx-sender seller))
    (try! (as-contract (ft-transfer? equity-token amount tx-sender tx-sender)))
    
    (map-set trading-orders
      { order-id: order-id }
      (merge order {
        is-filled: true,
        filled-at: (some stacks-block-height),
        buyer: (some tx-sender)
      })
    )
    
    (map-set user-orders
      { user: tx-sender, order-id: order-id }
      { exists: true }
    )
    
    (ok total-cost)
  )
)

(define-public (cancel-order (order-id uint))
  (let
    (
      (order (unwrap! (map-get? trading-orders { order-id: order-id }) ERR_ORDER_NOT_FOUND))
      (seller (get seller order))
      (amount (get amount order))
      (is-filled (get is-filled order))
    )
    (asserts! (is-eq tx-sender seller) ERR_UNAUTHORIZED)
    (asserts! (not is-filled) ERR_ORDER_ALREADY_FILLED)
    
    (try! (as-contract (ft-transfer? equity-token amount tx-sender seller)))
    
    (map-set trading-orders
      { order-id: order-id }
      (merge order { is-filled: true })
    )
    
    (ok amount)
  )
)

(define-public (auto-match-orders (sell-order-id uint) (buy-order-id uint))
  (let
    (
      (sell-order (unwrap! (map-get? trading-orders { order-id: sell-order-id }) ERR_ORDER_NOT_FOUND))
      (buy-order (unwrap! (map-get? trading-orders { order-id: buy-order-id }) ERR_ORDER_NOT_FOUND))
      (sell-price (get price-per-token sell-order))
      (buy-price (get price-per-token buy-order))
      (sell-amount (get amount sell-order))
      (buy-amount (get amount buy-order))
      (seller (get seller sell-order))
      (buyer (get seller buy-order))
      (matched-amount (if (<= sell-amount buy-amount) sell-amount buy-amount))
      (execution-price (/ (+ sell-price buy-price) u2))
      (total-cost (* matched-amount execution-price))
    )
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (not (get is-filled sell-order)) ERR_ORDER_ALREADY_FILLED)
    (asserts! (not (get is-filled buy-order)) ERR_ORDER_ALREADY_FILLED)
    (asserts! (<= sell-price buy-price) ERR_INVALID_PRICE)
    (asserts! (< stacks-block-height (get expires-at sell-order)) ERR_ORDER_EXPIRED)
    (asserts! (< stacks-block-height (get expires-at buy-order)) ERR_ORDER_EXPIRED)
    
    (try! (ft-transfer? equity-token total-cost buyer seller))
    (try! (as-contract (ft-transfer? equity-token matched-amount tx-sender buyer)))
    
    (if (is-eq matched-amount sell-amount)
      (map-set trading-orders
        { order-id: sell-order-id }
        (merge sell-order {
          is-filled: true,
          filled-at: (some stacks-block-height),
          buyer: (some buyer)
        })
      )
      (map-set trading-orders
        { order-id: sell-order-id }
        (merge sell-order {
          amount: (- sell-amount matched-amount)
        })
      )
    )
    
    (if (is-eq matched-amount buy-amount)
      (map-set trading-orders
        { order-id: buy-order-id }
        (merge buy-order {
          is-filled: true,
          filled-at: (some stacks-block-height),
          buyer: (some seller)
        })
      )
      (map-set trading-orders
        { order-id: buy-order-id }
        (merge buy-order {
          amount: (- buy-amount matched-amount)
        })
      )
    )
    
    (ok { matched-amount: matched-amount, execution-price: execution-price })
  )
)

(define-read-only (get-order (order-id uint))
  (map-get? trading-orders { order-id: order-id })
)

(define-read-only (get-order-counter)
  (var-get order-counter)
)

(define-read-only (is-order-active (order-id uint))
  (match (map-get? trading-orders { order-id: order-id })
    order
    (and 
      (not (get is-filled order))
      (< stacks-block-height (get expires-at order)))
    false
  )
)

(define-read-only (get-order-book-summary)
  {
    total-orders: (var-get order-counter),
    current-block: stacks-block-height
  }
)

(define-read-only (calculate-order-value (order-id uint))
  (match (map-get? trading-orders { order-id: order-id })
    order
    (* (get amount order) (get price-per-token order))
    u0
  )
)

(define-public (create-delegation (delegate principal) (delegation-type uint) (blocks-until-expiry uint))
  (let
    (
      (delegation-id (+ (var-get delegation-counter) u1))
      (expires-at (+ stacks-block-height blocks-until-expiry))
      (delegator-balance (ft-get-balance equity-token tx-sender))
      (existing-delegation (map-get? delegations { delegator: tx-sender, delegation-type: delegation-type }))
    )
    (asserts! (not (is-eq tx-sender delegate)) ERR_CANNOT_DELEGATE_TO_SELF)
    (asserts! (> delegator-balance u0) ERR_INSUFFICIENT_TOKENS)
    (asserts! (> blocks-until-expiry u0) ERR_INVALID_AMOUNT)
    (asserts! (< delegation-type u4) ERR_INVALID_DELEGATION_TYPE)
    (asserts! (is-none existing-delegation) ERR_DELEGATION_ALREADY_EXISTS)
    (asserts! (not (would-create-delegation-loop tx-sender delegate)) ERR_DELEGATION_LOOP)
    
    (map-set delegations
      { delegator: tx-sender, delegation-type: delegation-type }
      {
        delegate: delegate,
        created-at: stacks-block-height,
        expires-at: expires-at,
        is-active: true,
        delegation-id: delegation-id
      }
    )
    
    (map-set delegation-registry
      { delegation-id: delegation-id }
      {
        delegator: tx-sender,
        delegate: delegate,
        delegation-type: delegation-type,
        voting-power: delegator-balance,
        created-at: stacks-block-height,
        expires-at: expires-at,
        is-active: true
      }
    )
    
    (let
      (
        (current-powers (default-to { total-voting-power: u0, active-delegations: u0 } 
                        (map-get? delegate-powers { delegate: delegate, delegation-type: delegation-type })))
      )
      (map-set delegate-powers
        { delegate: delegate, delegation-type: delegation-type }
        {
          total-voting-power: (+ (get total-voting-power current-powers) delegator-balance),
          active-delegations: (+ (get active-delegations current-powers) u1)
        }
      )
    )
    
    (var-set delegation-counter delegation-id)
    (ok delegation-id)
  )
)

(define-public (revoke-delegation (delegation-type uint))
  (let
    (
      (delegation (unwrap! (map-get? delegations { delegator: tx-sender, delegation-type: delegation-type }) ERR_DELEGATION_NOT_FOUND))
      (delegate (get delegate delegation))
      (delegation-id (get delegation-id delegation))
      (voting-power (ft-get-balance equity-token tx-sender))
      (current-powers (unwrap! (map-get? delegate-powers { delegate: delegate, delegation-type: delegation-type }) ERR_DELEGATION_NOT_FOUND))
    )
    (asserts! (get is-active delegation) ERR_DELEGATION_NOT_FOUND)
    
    (map-set delegations
      { delegator: tx-sender, delegation-type: delegation-type }
      (merge delegation { is-active: false })
    )
    
    (map-set delegation-registry
      { delegation-id: delegation-id }
      (merge (unwrap-panic (map-get? delegation-registry { delegation-id: delegation-id })) { is-active: false })
    )
    
    (map-set delegate-powers
      { delegate: delegate, delegation-type: delegation-type }
      {
        total-voting-power: (- (get total-voting-power current-powers) voting-power),
        active-delegations: (- (get active-delegations current-powers) u1)
      }
    )
    
    (ok true)
  )
)

(define-public (transfer-delegation (from-delegate principal) (to-delegate principal) (delegation-type uint))
  (let
    (
      (delegation (unwrap! (map-get? delegations { delegator: tx-sender, delegation-type: delegation-type }) ERR_DELEGATION_NOT_FOUND))
      (delegation-id (get delegation-id delegation))
      (voting-power (ft-get-balance equity-token tx-sender))
      (from-powers (unwrap! (map-get? delegate-powers { delegate: from-delegate, delegation-type: delegation-type }) ERR_DELEGATION_NOT_FOUND))
      (to-powers (default-to { total-voting-power: u0, active-delegations: u0 } 
                  (map-get? delegate-powers { delegate: to-delegate, delegation-type: delegation-type })))
    )
    (asserts! (not (is-eq tx-sender to-delegate)) ERR_CANNOT_DELEGATE_TO_SELF)
    (asserts! (is-eq (get delegate delegation) from-delegate) ERR_UNAUTHORIZED)
    (asserts! (get is-active delegation) ERR_DELEGATION_NOT_FOUND)
    (asserts! (< stacks-block-height (get expires-at delegation)) ERR_DELEGATION_EXPIRED)
    (asserts! (not (would-create-delegation-loop tx-sender to-delegate)) ERR_DELEGATION_LOOP)
    
    (map-set delegations
      { delegator: tx-sender, delegation-type: delegation-type }
      (merge delegation { delegate: to-delegate })
    )
    
    (map-set delegation-registry
      { delegation-id: delegation-id }
      (merge (unwrap-panic (map-get? delegation-registry { delegation-id: delegation-id })) { delegate: to-delegate })
    )
    
    (map-set delegate-powers
      { delegate: from-delegate, delegation-type: delegation-type }
      {
        total-voting-power: (- (get total-voting-power from-powers) voting-power),
        active-delegations: (- (get active-delegations from-powers) u1)
      }
    )
    
    (map-set delegate-powers
      { delegate: to-delegate, delegation-type: delegation-type }
      {
        total-voting-power: (+ (get total-voting-power to-powers) voting-power),
        active-delegations: (+ (get active-delegations to-powers) u1)
      }
    )
    
    (ok true)
  )
)

(define-public (execute-delegated-action (action-type uint) (target principal) (amount uint))
  (let
    (
      (delegate-power (default-to { total-voting-power: u0, active-delegations: u0 } 
                      (map-get? delegate-powers { delegate: tx-sender, delegation-type: action-type })))
      (required-power (/ amount u2))
    )
    (asserts! (>= (get total-voting-power delegate-power) required-power) ERR_INSUFFICIENT_TOKENS)
    (asserts! (> (get active-delegations delegate-power) u0) ERR_DELEGATION_NOT_FOUND)
    
    (if (is-eq action-type u1)
      (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (ok true)
      )
      (if (is-eq action-type u2)
        (begin
          (try! (ft-transfer? equity-token amount tx-sender target))
          (ok true)
        )
        (ok false)
      )
    )
  )
)

(define-read-only (get-delegation (delegator principal) (delegation-type uint))
  (map-get? delegations { delegator: delegator, delegation-type: delegation-type })
)

(define-read-only (get-delegation-by-id (delegation-id uint))
  (map-get? delegation-registry { delegation-id: delegation-id })
)

(define-read-only (get-delegate-power (delegate principal) (delegation-type uint))
  (default-to { total-voting-power: u0, active-delegations: u0 } 
              (map-get? delegate-powers { delegate: delegate, delegation-type: delegation-type }))
)

(define-read-only (is-delegation-active (delegator principal) (delegation-type uint))
  (match (map-get? delegations { delegator: delegator, delegation-type: delegation-type })
    delegation
    (and 
      (get is-active delegation)
      (< stacks-block-height (get expires-at delegation)))
    false
  )
)

(define-read-only (get-delegation-counter)
  (var-get delegation-counter)
)

(define-read-only (would-create-delegation-loop (delegator principal) (delegate principal))
  (let
    (
      (delegate-delegation (map-get? delegations { delegator: delegate, delegation-type: u1 }))
    )
    (match delegate-delegation
      delegation
      (if (get is-active delegation)
        (is-eq (get delegate delegation) delegator)
        false)
      false
    )
  )
)

(define-read-only (calculate-effective-voting-power (account principal))
  (let
    (
      (base-power (ft-get-balance equity-token account))
      (delegated-power-governance (get total-voting-power (get-delegate-power account u1)))
      (delegated-power-transfer (get total-voting-power (get-delegate-power account u2)))
    )
    {
      base-voting-power: base-power,
      delegated-governance-power: delegated-power-governance,
      delegated-transfer-power: delegated-power-transfer,
      total-effective-power: (+ base-power delegated-power-governance)
    }
  )
)

