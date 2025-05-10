;; LEI Registry Smart Contract
;; This contract provides functionality for registering and managing Legal Entity Identifiers (LEIs)
;; LEIs are 20-character alphanumeric codes that uniquely identify legal entities participating in financial transactions

;; Error codes
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-ALREADY-REGISTERED (err u101))
(define-constant ERR-INVALID-LEI (err u102))
(define-constant ERR-NOT-FOUND (err u103))
(define-constant ERR-EXPIRED (err u104))
(define-constant ERR-INVALID-DATE (err u105))
(define-constant ERR-INVALID-STATUS (err u106))
(define-constant ERR-INVALID-ADDRESS (err u107))

;; Define data structures for storing LEI information
(define-map lei-registry
  { lei: (string-ascii 20) }
  {
    entity-name: (string-utf8 256),
    registration-date: uint,
    expiration-date: uint,
    status: (string-ascii 20),
    country-code: (string-ascii 2),
    legal-form: (string-utf8 100),
    registration-authority: (string-utf8 100),
    owner: principal,
    last-update: uint
  }
)

;; Map to track LEIs by principal address
(define-map principal-lei-map
  { owner: principal }
  { leis: (list 20 (string-ascii 20)) }
)

;; Map to track LEI registration status history
(define-map lei-status-history
  { lei: (string-ascii 20) }
  { statuses: (list 50 { status: (string-ascii 20), timestamp: uint }) }
)

;; Map to store contract administrators
(define-map administrators
  { admin: principal }
  { active: bool }
)

;; Define contract owner - only this principal can add/remove administrators
(define-data-var contract-owner principal tx-sender)

;; Contract governance
(define-public (set-contract-owner (new-owner principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    (ok (var-set contract-owner new-owner))
  )
)

(define-public (add-administrator (admin principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    (ok (map-set administrators { admin: admin } { active: true }))
  )
)

(define-public (remove-administrator (admin principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    (ok (map-set administrators { admin: admin } { active: false }))
  )
)

;; Helper function to check if caller is authorized
(define-private (is-authorized)
  (or
    (is-eq tx-sender (var-get contract-owner))
    (default-to false (get active (map-get? administrators { admin: tx-sender })))
  )
)

;; Helper function to validate LEI format
;; LEI is 20 characters: 4 alphanumeric, 2 country code, 12 alphanumeric, 2 check digits
(define-private (is-valid-lei (lei (string-ascii 20)))
  (and
    (is-eq (len lei) u20)
    (is-lei-format-valid lei)
  )
)

;; Additional LEI format validation logic
(define-private (is-lei-format-valid (lei (string-ascii 20)))
  (let
    (
      (country-code (slice lei u4 u2))
    )
    ;; This is a simplified validation
    ;; In a full implementation, you would add more validation rules
    (> (len country-code) u0)
  )
)

;; Function to add a new LEI to user's list
(define-private (add-lei-to-principal (lei (string-ascii 20)) (owner principal))
  (let 
    (
      (existing-leis (default-to { leis: (list) } (map-get? principal-lei-map { owner: owner })))
      (current-list (get leis existing-leis))
      (new-list (unwrap! (as-max-len? (append current-list lei) u20) ERR-ALREADY-REGISTERED))
    )
    (map-set principal-lei-map
      { owner: owner }
      { leis: new-list }
    )
  )
)

;; Function to add status to LEI history
(define-private (add-status-to-history (lei (string-ascii 20)) (status (string-ascii 20)))
  (let
    (
      (existing-history (default-to { statuses: (list) } (map-get? lei-status-history { lei: lei })))
      (current-list (get statuses existing-history))
      (new-status { status: status, timestamp: block-height })
      (new-list (unwrap! (as-max-len? (append current-list new-status) u50) ERR-ALREADY-REGISTERED))
    )
    (map-set lei-status-history
      { lei: lei }
      { statuses: new-list }
    )
  )
)

;; Register a new LEI
(define-public (register-lei 
  (lei (string-ascii 20))
  (entity-name (string-utf8 256))
  (expiration-date uint)
  (country-code (string-ascii 2))
  (legal-form (string-utf8 100))
  (registration-authority (string-utf8 100))
)
  (begin
    ;; Check authorization
    (asserts! (is-authorized) ERR-NOT-AUTHORIZED)
    
    ;; Check LEI validity
    (asserts! (is-valid-lei lei) ERR-INVALID-LEI)
    
    ;; Check that LEI is not already registered
    (asserts! (is-none (map-get? lei-registry { lei: lei })) ERR-ALREADY-REGISTERED)
    
    ;; Check expiration date is in the future
    (asserts! (> expiration-date block-height) ERR-INVALID-DATE)
    
    ;; Register the LEI
    (try! (map-set lei-registry
      { lei: lei }
      {
        entity-name: entity-name,
        registration-date: block-height,
        expiration-date: expiration-date,
        status: "ACTIVE",
        country-code: country-code,
        legal-form: legal-form,
        registration-authority: registration-authority,
        owner: tx-sender,
        last-update: block-height
      }
    ))
    
    ;; Add LEI to principal's list
    (try! (add-lei-to-principal lei tx-sender))
    
    ;; Add initial status to history
    (try! (add-status-to-history lei "ACTIVE"))
    
    (ok true)
  )
)

;; Renew an LEI by extending its expiration date
(define-public (renew-lei (lei (string-ascii 20)) (new-expiration-date uint))
  (let
    (
      (lei-data (unwrap! (map-get? lei-registry { lei: lei }) ERR-NOT-FOUND))
      (owner (get owner lei-data))
    )
    ;; Check authorization
    (asserts! (or (is-authorized) (is-eq tx-sender owner)) ERR-NOT-AUTHORIZED)
    
    ;; Check that new expiration date is in the future
    (asserts! (> new-expiration-date block-height) ERR-INVALID-DATE)
    
    ;; Check that new expiration date is after current one
    (asserts! (> new-expiration-date (get expiration-date lei-data)) ERR-INVALID-DATE)
    
    ;; Update the LEI
    (try! (map-set lei-registry
      { lei: lei }
      (merge lei-data {
        expiration-date: new-expiration-date,
        status: "ACTIVE",
        last-update: block-height
      })
    ))
    
    ;; Add renewal status to history if status was previously EXPIRED
    (if (is-eq (get status lei-data) "EXPIRED")
      (try! (add-status-to-history lei "ACTIVE"))
      true
    )
    
    (ok true)
  )
)

;; Update LEI information
(define-public (update-lei-info
  (lei (string-ascii 20))
  (entity-name (string-utf8 256))
  (country-code (string-ascii 2))
  (legal-form (string-utf8 100))
  (registration-authority (string-utf8 100))
)
  (let
    (
      (lei-data (unwrap! (map-get? lei-registry { lei: lei }) ERR-NOT-FOUND))
      (owner (get owner lei-data))
    )
    ;; Check authorization
    (asserts! (or (is-authorized) (is-eq tx-sender owner)) ERR-NOT-AUTHORIZED)
    
    ;; Update the LEI
    (ok (map-set lei-registry
      { lei: lei }
      (merge lei-data {
        entity-name: entity-name,
        country-code: country-code,
        legal-form: legal-form,
        registration-authority: registration-authority,
        last-update: block-height
      })
    ))
  )
)

;; Change LEI status (ACTIVE, LAPSED, RETIRED, MERGED, DUPLICATE, etc.)
(define-public (change-lei-status (lei (string-ascii 20)) (new-status (string-ascii 20)))
  (let
    (
      (lei-data (unwrap! (map-get? lei-registry { lei: lei }) ERR-NOT-FOUND))
    )
    ;; Check authorization - only admins can change status
    (asserts! (is-authorized) ERR-NOT-AUTHORIZED)
    
    ;; Validate status
    (asserts! (or 
      (is-eq new-status "ACTIVE")
      (is-eq new-status "LAPSED")
      (is-eq new-status "RETIRED")
      (is-eq new-status "MERGED")
      (is-eq new-status "DUPLICATE")
      (is-eq new-status "EXPIRED")
    ) ERR-INVALID-STATUS)
    
    ;; Update the LEI status
    (try! (map-set lei-registry
      { lei: lei }
      (merge lei-data {
        status: new-status,
        last-update: block-height
      })
    ))
    
    ;; Add status change to history
    (try! (add-status-to-history lei new-status))
    
    (ok true)
  )
)

;; Transfer LEI ownership
(define-public (transfer-lei (lei (string-ascii 20)) (new-owner principal))
  (let
    (
      (lei-data (unwrap! (map-get? lei-registry { lei: lei }) ERR-NOT-FOUND))
      (current-owner (get owner lei-data))
    )
    ;; Check authorization
    (asserts! (or (is-authorized) (is-eq tx-sender current-owner)) ERR-NOT-AUTHORIZED)
    
    ;; Validate new owner address
    (asserts! (not (is-eq new-owner current-owner)) ERR-INVALID-ADDRESS)
    
    ;; Update the LEI owner
    (try! (map-set lei-registry
      { lei: lei }
      (merge lei-data {
        owner: new-owner,
        last-update: block-height
      })
    ))
    
    ;; Add LEI to new owner's list
    (try! (add-lei-to-principal lei new-owner))
    
    ;; Note: We could also remove the LEI from the previous owner's list
    ;; but for historical tracking, we're keeping it in this implementation
    
    (ok true)
  )
)

;; Read-only function to get LEI information
(define-read-only (get-lei-info (lei (string-ascii 20)))
  (map-get? lei-registry { lei: lei })
)

;; Check if an LEI is active
(define-read-only (is-lei-active (lei (string-ascii 20)))
  (let
    (
      (lei-data (map-get? lei-registry { lei: lei }))
    )
    (if (is-some lei-data)
      (let
        (
          (unwrapped-data (unwrap! lei-data false))
          (is-active (is-eq (get status unwrapped-data) "ACTIVE"))
          (is-not-expired (> (get expiration-date unwrapped-data) block-height))
        )
        (and is-active is-not-expired)
      )
      false
    )
  )
)

;; Get all LEIs owned by a principal
(define-read-only (get-leis-by-principal (owner principal))
  (default-to { leis: (list) } (map-get? principal-lei-map { owner: owner }))
)

;; Get LEI status history
(define-read-only (get-lei-status-history (lei (string-ascii 20)))
  (default-to { statuses: (list) } (map-get? lei-status-history { lei: lei }))
)

;; Check if a principal is an administrator
(define-read-only (is-admin (address principal))
  (default-to false (get active (map-get? administrators { admin: address })))
)

;; Verify LEI validity, authentication, and expiration in one call
(define-read-only (verify-lei (lei (string-ascii 20)))
  (let
    (
      (lei-data (map-get? lei-registry { lei: lei }))
    )
    (if (is-some lei-data)
      (let
        (
          (unwrapped-data (unwrap! lei-data { status: "NOT_FOUND", expiration-date: u0 }))
          (status (get status unwrapped-data))
          (expiration (get expiration-date unwrapped-data))
          (is-active (is-eq status "ACTIVE"))
          (is-expired (< expiration block-height))
        )
        (cond
          ((not is-active) (err u201)) ;; Not active
          (is-expired (err u202))      ;; Expired
          (true (ok unwrapped-data))   ;; Valid
        )
      )
      ERR-NOT-FOUND
    )
  )
)

;; Auto-expire function - can be called periodically to update status of expired LEIs
(define-public (auto-expire-leis (leis (list 20 (string-ascii 20))))
  (begin
    ;; Only authorized users can trigger this
    (asserts! (is-authorized) ERR-NOT-AUTHORIZED)
    
    ;; Process each LEI in the list
    (map check-and-expire-lei leis)
    
    (ok true)
  )
)

;; Helper function to check and expire a single LEI
(define-private (check-and-expire-lei (lei (string-ascii 20)))
  (let
    (
      (lei-data (map-get? lei-registry { lei: lei }))
    )
    (if (is-some lei-data)
      (let
        (
          (unwrapped-data (unwrap! lei-data { expiration-date: u0, status: "" }))
          (expiration (get expiration-date unwrapped-data))
          (status (get status unwrapped-data))
          (needs-expire (and (< expiration block-height) (is-eq status "ACTIVE")))
        )
        (if needs-expire
          (begin
            (map-set lei-registry
              { lei: lei }
              (merge unwrapped-data {
                status: "EXPIRED",
                last-update: block-height
              })
            )
            (add-status-to-history lei "EXPIRED")
            true
          )
          false
        )
      )
      false
    )
  )
)

;; Initialize the contract by setting the initial contract owner
(define-private (initialize)
  (begin
    (map-set administrators { admin: tx-sender } { active: true })
    true
  )
)

;; Make sure the contract is initialized when deployed
(initialize)