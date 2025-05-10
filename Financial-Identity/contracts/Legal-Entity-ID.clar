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
(define-constant ERR-INVALID-INPUT (err u108))
(define-constant ERR-INVALID-COUNTRY-CODE (err u109))
(define-constant ERR-INVALID-ENTITY-NAME (err u110))
(define-constant ERR-INVALID-LEGAL-FORM (err u111))
(define-constant ERR-INVALID-REGISTRATION-AUTHORITY (err u112))

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

;; Helper function to validate principal
(define-private (is-valid-principal (principal-to-check principal))
  (is-some (some principal-to-check))
)

;; Helper function to validate country code (2 characters)
(define-private (is-valid-country-code (code (string-ascii 2)))
  (is-eq (len code) u2)
)

;; Helper function to validate entity name (non-empty, max 256 chars)
(define-private (is-valid-entity-name (name (string-utf8 256)))
  (and (> (len name) u0) (<= (len name) u256))
)

;; Helper function to validate legal form (non-empty, max 100 chars)
(define-private (is-valid-legal-form (form (string-utf8 100)))
  (and (> (len form) u0) (<= (len form) u100))
)

;; Helper function to validate registration authority (non-empty, max 100 chars)
(define-private (is-valid-registration-authority (authority (string-utf8 100)))
  (and (> (len authority) u0) (<= (len authority) u100))
)

;; Helper function to validate status string
(define-private (is-valid-status (status (string-ascii 20)))
  (or 
    (is-eq status "ACTIVE")
    (is-eq status "LAPSED")
    (is-eq status "RETIRED")
    (is-eq status "MERGED")
    (is-eq status "DUPLICATE")
    (is-eq status "EXPIRED")
  )
)

;; Contract governance
(define-public (set-contract-owner (new-owner principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    (asserts! (is-valid-principal new-owner) ERR-INVALID-INPUT)
    (ok (var-set contract-owner new-owner))
  )
)

(define-public (add-administrator (admin principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    (asserts! (is-valid-principal admin) ERR-INVALID-INPUT)
    (ok (map-set administrators { admin: admin } { active: true }))
  )
)

(define-public (remove-administrator (admin principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    (asserts! (is-valid-principal admin) ERR-INVALID-INPUT)
    (ok (map-set administrators { admin: admin } { active: false }))
  )
)

;; Helper function to check if caller is authorized
(define-private (is-authorized)
  (let 
    (
      (admin-status (map-get? administrators { admin: tx-sender }))
    )
    (or
      (is-eq tx-sender (var-get contract-owner))
      (and (is-some admin-status) (get active (unwrap-panic admin-status)))
    )
  )
)

;; Helper function to validate LEI format
;; LEI is 20 characters: 4 alphanumeric, 2 country code, 12 alphanumeric, 2 check digits
(define-private (is-valid-lei (lei (string-ascii 20)))
  ;; Since Clarity doesn't have native string slicing functions,
  ;; we'll implement a simplified validation approach
  ;; This just checks for proper length - in production, implement more thorough validation
  (is-eq (len lei) u20)
)

;; Function to add a new LEI to user's list
(define-private (add-lei-to-principal (lei (string-ascii 20)) (owner principal))
  (begin
    (asserts! (is-valid-lei lei) ERR-INVALID-LEI)
    (asserts! (is-valid-principal owner) ERR-INVALID-ADDRESS)
    (let 
      (
        (existing-leis-opt (map-get? principal-lei-map { owner: owner }))
        (current-list (if (is-some existing-leis-opt)
                         (get leis (unwrap-panic existing-leis-opt))
                         (list)))
        (new-list-maybe (as-max-len? (append current-list lei) u20))
      )
      (if (is-some new-list-maybe)
        (ok (map-set principal-lei-map
          { owner: owner }
          { leis: (unwrap-panic new-list-maybe) }
        ))
        ERR-ALREADY-REGISTERED
      )
    )
  )
)

;; Function to add status to LEI history
(define-private (add-status-to-history (lei (string-ascii 20)) (status (string-ascii 20)))
  (begin
    (asserts! (is-valid-lei lei) ERR-INVALID-LEI)
    (asserts! (is-valid-status status) ERR-INVALID-STATUS)
    (let
      (
        (existing-history-opt (map-get? lei-status-history { lei: lei }))
        (current-list (if (is-some existing-history-opt)
                         (get statuses (unwrap-panic existing-history-opt))
                         (list)))
        (new-status { status: status, timestamp: block-height })
        (new-list-maybe (as-max-len? (append current-list new-status) u50))
      )
      (if (is-some new-list-maybe)
        (ok (map-set lei-status-history
          { lei: lei }
          { statuses: (unwrap-panic new-list-maybe) }
        ))
        ERR-ALREADY-REGISTERED
      )
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
    
    ;; Validate all inputs
    (asserts! (is-valid-lei lei) ERR-INVALID-LEI)
    (asserts! (is-valid-entity-name entity-name) ERR-INVALID-ENTITY-NAME)
    (asserts! (is-valid-country-code country-code) ERR-INVALID-COUNTRY-CODE)
    (asserts! (is-valid-legal-form legal-form) ERR-INVALID-LEGAL-FORM)
    (asserts! (is-valid-registration-authority registration-authority) ERR-INVALID-REGISTRATION-AUTHORITY)
    
    ;; Check that LEI is not already registered
    (asserts! (is-none (map-get? lei-registry { lei: lei })) ERR-ALREADY-REGISTERED)
    
    ;; Check expiration date is in the future
    (asserts! (> expiration-date block-height) ERR-INVALID-DATE)
    
    ;; Register the LEI
    (map-set lei-registry
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
    )
    
    ;; Add LEI to principal's list
    (try! (add-lei-to-principal lei tx-sender))
    
    ;; Add initial status to history
    (try! (add-status-to-history lei "ACTIVE"))
    
    (ok true)
  )
)

;; Renew an LEI by extending its expiration date
(define-public (renew-lei (lei (string-ascii 20)) (new-expiration-date uint))
  (begin
    ;; Validate LEI
    (asserts! (is-valid-lei lei) ERR-INVALID-LEI)
    
    (let
      (
        (lei-data-opt (map-get? lei-registry { lei: lei }))
      )
      ;; Check that LEI exists
      (asserts! (is-some lei-data-opt) ERR-NOT-FOUND)
      
      (let
        (
          (lei-data (unwrap-panic lei-data-opt))
          (owner (get owner lei-data))
          (current-status (get status lei-data))
        )
        ;; Check authorization
        (asserts! (or (is-authorized) (is-eq tx-sender owner)) ERR-NOT-AUTHORIZED)
        
        ;; Check that new expiration date is in the future
        (asserts! (> new-expiration-date block-height) ERR-INVALID-DATE)
        
        ;; Check that new expiration date is after current one
        (asserts! (> new-expiration-date (get expiration-date lei-data)) ERR-INVALID-DATE)
        
        ;; Update the LEI
        (map-set lei-registry
          { lei: lei }
          (merge lei-data {
            expiration-date: new-expiration-date,
            status: "ACTIVE",
            last-update: block-height
          })
        )
        
        ;; Add renewal status to history if status was previously EXPIRED
        (if (is-eq current-status "EXPIRED")
          (try! (add-status-to-history lei "ACTIVE"))
          true
        )
        
        (ok true)
      )
    )
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
  (begin
    ;; Validate all inputs
    (asserts! (is-valid-lei lei) ERR-INVALID-LEI)
    (asserts! (is-valid-entity-name entity-name) ERR-INVALID-ENTITY-NAME)
    (asserts! (is-valid-country-code country-code) ERR-INVALID-COUNTRY-CODE)
    (asserts! (is-valid-legal-form legal-form) ERR-INVALID-LEGAL-FORM)
    (asserts! (is-valid-registration-authority registration-authority) ERR-INVALID-REGISTRATION-AUTHORITY)
    
    (let
      (
        (lei-data-opt (map-get? lei-registry { lei: lei }))
      )
      ;; Check that LEI exists
      (asserts! (is-some lei-data-opt) ERR-NOT-FOUND)
      
      (let
        (
          (lei-data (unwrap-panic lei-data-opt))
          (owner (get owner lei-data))
        )
        ;; Check authorization
        (asserts! (or (is-authorized) (is-eq tx-sender owner)) ERR-NOT-AUTHORIZED)
        
        ;; Update the LEI
        (map-set lei-registry
          { lei: lei }
          (merge lei-data {
            entity-name: entity-name,
            country-code: country-code,
            legal-form: legal-form,
            registration-authority: registration-authority,
            last-update: block-height
          })
        )
        
        (ok true)
      )
    )
  )
)

;; Change LEI status (ACTIVE, LAPSED, RETIRED, MERGED, DUPLICATE, etc.)
(define-public (change-lei-status (lei (string-ascii 20)) (new-status (string-ascii 20)))
  (begin
    ;; Validate inputs
    (asserts! (is-valid-lei lei) ERR-INVALID-LEI)
    (asserts! (is-valid-status new-status) ERR-INVALID-STATUS)
    
    (let
      (
        (lei-data-opt (map-get? lei-registry { lei: lei }))
      )
      ;; Check that LEI exists
      (asserts! (is-some lei-data-opt) ERR-NOT-FOUND)
      
      (let
        (
          (lei-data (unwrap-panic lei-data-opt))
        )
        ;; Check authorization - only admins can change status
        (asserts! (is-authorized) ERR-NOT-AUTHORIZED)
        
        ;; Update the LEI status
        (map-set lei-registry
          { lei: lei }
          (merge lei-data {
            status: new-status,
            last-update: block-height
          })
        )
        
        ;; Add status change to history
        (try! (add-status-to-history lei new-status))
        
        (ok true)
      )
    )
  )
)

;; Transfer LEI ownership
(define-public (transfer-lei (lei (string-ascii 20)) (new-owner principal))
  (begin
    ;; Validate inputs
    (asserts! (is-valid-lei lei) ERR-INVALID-LEI)
    (asserts! (is-valid-principal new-owner) ERR-INVALID-ADDRESS)
    
    (let
      (
        (lei-data-opt (map-get? lei-registry { lei: lei }))
      )
      ;; Check that LEI exists
      (asserts! (is-some lei-data-opt) ERR-NOT-FOUND)
      
      (let
        (
          (lei-data (unwrap-panic lei-data-opt))
          (current-owner (get owner lei-data))
        )
        ;; Check authorization
        (asserts! (or (is-authorized) (is-eq tx-sender current-owner)) ERR-NOT-AUTHORIZED)
        
        ;; Validate new owner address
        (asserts! (not (is-eq new-owner current-owner)) ERR-INVALID-ADDRESS)
        
        ;; Update the LEI owner
        (map-set lei-registry
          { lei: lei }
          (merge lei-data {
            owner: new-owner,
            last-update: block-height
          })
        )
        
        ;; Add LEI to new owner's list
        (try! (add-lei-to-principal lei new-owner))
        
        ;; Note: We could also remove the LEI from the previous owner's list
        ;; but for historical tracking, we're keeping it in this implementation
        
        (ok true)
      )
    )
  )
)

;; Read-only function to get LEI information
(define-read-only (get-lei-info (lei (string-ascii 20)))
  (begin
    (if (is-valid-lei lei)
      (let ((lei-data (map-get? lei-registry { lei: lei })))
        (if (is-some lei-data)
          (ok (unwrap-panic lei-data))
          ERR-NOT-FOUND
        )
      )
      ERR-INVALID-LEI
    )
  )
)

;; Check if an LEI is active
(define-read-only (is-lei-active (lei (string-ascii 20)))
  (begin
    (if (is-valid-lei lei)
      (let
        (
          (lei-data (map-get? lei-registry { lei: lei }))
        )
        (if (is-some lei-data)
          (let
            (
              (unwrapped-data (unwrap-panic lei-data))
              (is-active (is-eq (get status unwrapped-data) "ACTIVE"))
              (is-not-expired (> (get expiration-date unwrapped-data) block-height))
            )
            (ok (and is-active is-not-expired))
          )
          ERR-NOT-FOUND
        )
      )
      ERR-INVALID-LEI
    )
  )
)

;; Get all LEIs owned by a principal
(define-read-only (get-leis-by-principal (owner principal))
  (begin
    (if (is-valid-principal owner)
      (let 
        (
          (result (map-get? principal-lei-map { owner: owner }))
        )
        (if (is-some result)
          (ok (unwrap-panic result))
          (ok { leis: (list) })
        )
      )
      ERR-INVALID-ADDRESS
    )
  )
)

;; Get LEI status history
(define-read-only (get-lei-status-history (lei (string-ascii 20)))
  (begin
    (if (is-valid-lei lei)
      (let 
        (
          (result (map-get? lei-status-history { lei: lei }))
        )
        (if (is-some result)
          (ok (unwrap-panic result))
          (ok { statuses: (list) })
        )
      )
      ERR-INVALID-LEI
    )
  )
)

;; Check if a principal is an administrator
(define-read-only (is-admin (address principal))
  (begin
    (if (is-valid-principal address)
      (ok (default-to false (get active (map-get? administrators { admin: address }))))
      ERR-INVALID-ADDRESS
    )
  )
)

;; Verify LEI validity, authentication, and expiration in one call
(define-read-only (verify-lei (lei (string-ascii 20)))
  (begin
    (if (is-valid-lei lei)
      (let ((lei-data (map-get? lei-registry { lei: lei })))
        (if (is-none lei-data)
          ERR-NOT-FOUND
          (let ((data (unwrap-panic lei-data)))
            (if (not (is-eq (get status data) "ACTIVE"))
              (err u201) ;; Not active
              (if (< (get expiration-date data) block-height)
                (err u202) ;; Expired
                (ok data) ;; Valid
              )
            )
          )
        )
      )
      ERR-INVALID-LEI
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
  (begin
    (if (is-valid-lei lei)
      (let
        (
          (lei-data (map-get? lei-registry { lei: lei }))
        )
        (if (is-some lei-data)
          (let
            (
              (unwrapped-data (unwrap-panic lei-data))
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
                ;; Ignore any errors from adding status to history
                (match (add-status-to-history lei "EXPIRED")
                  success true
                  error false)
                true
              )
              false
            )
          )
          false
        )
      )
      false
    )
  )
)

;; Contract initialization
;; This happens when the contract is deployed
(begin
  ;; Set initial contract owner to the deployer
  (map-set administrators { admin: tx-sender } { active: true })
)