!
! Copyright (C) 2001-2007 Quantum ESPRESSO group
! This file is distributed under the terms of the
! GNU General Public License. See the file `License'
! in the root directory of the present distribution,
! or http://www.gnu.org/copyleft/gpl.txt .
!
!
!----------------------------------------------------------------------------
SUBROUTINE rotate_wfc_k( npwx, npw, nstart, nbnd, npol, psi, overlap, evc, e )
  !----------------------------------------------------------------------------
  !
  ! ... Serial version of rotate_wfc for colinear, k-point calculations
  !
  USE kinds,         ONLY : DP
  USE mp_bands,      ONLY : intra_bgrp_comm
  USE mp,            ONLY : mp_sum
  USE cpu_gpu_interface
  !
  IMPLICIT NONE
  !
  ! ... I/O variables
  !
  INTEGER, INTENT(IN) :: npw, npwx, nstart, nbnd, npol
    ! dimension of the matrix to be diagonalized
    ! leading dimension of matrix psi, as declared in the calling pgm unit
    ! input number of states
    ! output number of states
    ! number of spin polarizations
  LOGICAL :: overlap
    ! if .FALSE. : S|psi> not needed
  COMPLEX(DP) :: psi(npwx*npol,nstart), evc(npwx*npol,nbnd)
    ! input and output eigenvectors (may overlap)
  REAL(DP) :: e(nbnd)
    ! eigenvalues
  !
  ! ... local variables
  !
  INTEGER :: kdim, kdmx
  COMPLEX(DP), ALLOCATABLE :: aux(:,:), hc(:,:), sc(:,:), vc(:,:)
  REAL(DP),    ALLOCATABLE :: en(:)
  !
  IF ( npol == 1 ) THEN
     !
     kdim = npw
     kdmx = npwx
     !
  ELSE
     !
     kdim = npwx*npol
     kdmx = npwx*npol
     !
  END IF
  !

  ALLOCATE( aux(kdmx, nstart ) )    
  ALLOCATE( hc( nstart, nstart) )    
  ALLOCATE( sc( nstart, nstart) )    
  ALLOCATE( vc( nstart, nstart) )    
  ALLOCATE( en( nstart ) )
  !
  ! ... Set up the Hamiltonian and Overlap matrix on the subspace :
  !
  ! ...      H_ij = <psi_i| H |psi_j>     S_ij = <psi_i| S |psi_j>
  !
  CALL h_psi( npwx, npw, nstart, psi, aux )
  !
  call ZGEMM( 'C', 'N', nstart, nstart, kdim, ( 1.D0, 0.D0 ), psi, kdmx,  aux, kdmx, ( 0.D0, 0.D0 ), hc, nstart )
  !            
  CALL mp_sum(  hc , intra_bgrp_comm )
  !
  IF ( overlap ) THEN
     !
     CALL s_psi( npwx, npw, nstart, psi, aux )
     !
     CALL ZGEMM( 'C', 'N', nstart, nstart, kdim, ( 1.D0, 0.D0 ), psi, kdmx,  aux, kdmx, ( 0.D0, 0.D0 ), sc, nstart )
     !
  ELSE
     !
     CALL ZGEMM( 'C', 'N', nstart, nstart, kdim, ( 1.D0, 0.D0 ), psi, kdmx, psi, kdmx, ( 0.D0, 0.D0 ), sc, nstart )
     !  
  END IF
  !
  CALL mp_sum(  sc , intra_bgrp_comm )
  !
  ! ... Diagonalize
  !
  CALL cdiaghg( nstart, nbnd, hc, sc, nstart, en, vc )
  !
  e(:) = en(1:nbnd)
  !
  ! ...  update the basis set
  !  
  CALL ZGEMM( 'N', 'N', kdim, nbnd, nstart, ( 1.D0, 0.D0 ), psi, kdmx, vc, nstart, ( 0.D0, 0.D0 ), aux, kdmx )
  !     
  evc(:,:) = aux(:,1:nbnd)
  !
  DEALLOCATE( en )
  DEALLOCATE( vc )
  DEALLOCATE( sc )
  DEALLOCATE( hc )
  DEALLOCATE( aux )
  !
  RETURN
  !
END SUBROUTINE rotate_wfc_k
!
#ifdef USE_CUDA
!----------------------------------------------------------------------------
SUBROUTINE rotate_wfc_k_gpu( npwx, npw, nstart, nbnd, npol, psi, psi_d, overlap, evc, evc_d, e, e_d )
  !----------------------------------------------------------------------------
  !
  ! ... Serial version of rotate_wfc for colinear, k-point calculations
  !
  USE kinds,         ONLY : DP
  USE mp_bands,      ONLY : intra_bgrp_comm
  USE mp,            ONLY : mp_sum
  USE cudafor
  USE cublas,        ONLY : cublasZgemm
  USE cdiaghg_compute_gpu_module, ONLY : cdiaghg_gpu
  USE cpu_gpu_interface
  !
  IMPLICIT NONE
  !
  ! ... I/O variables
  !
  INTEGER, INTENT(IN) :: npw, npwx, nstart, nbnd, npol
    ! dimension of the matrix to be diagonalized
    ! leading dimension of matrix psi, as declared in the calling pgm unit
    ! input number of states
    ! output number of states
    ! number of spin polarizations
  LOGICAL :: overlap
    ! if .FALSE. : S|psi> not needed
  COMPLEX(DP) :: psi(npwx*npol,nstart), evc(npwx*npol,nbnd)
    ! input and output eigenvectors (may overlap)
  REAL(DP) :: e(nbnd)
    ! eigenvalues

  COMPLEX(DP), DEVICE :: psi_d(npwx*npol,nstart), evc_d(npwx*npol,nbnd)
    ! input and output eigenvectors (may overlap)
  REAL(DP), DEVICE :: e_d(nbnd)
    ! eigenvalues

  !
  ! ... local variables
  !
  INTEGER :: kdim, kdmx
  COMPLEX(DP), ALLOCATABLE :: aux(:,:), hc(:,:), sc(:,:), vc(:,:)
  REAL(DP),    ALLOCATABLE :: en(:)
  !
  COMPLEX(DP), ALLOCATABLE, DEVICE :: aux_d(:,:), hc_d(:,:), sc_d(:,:), vc_d(:,:)
  REAL(DP),    ALLOCATABLE, DEVICE :: en_d(:)

  !ATTRIBUTES( DEVICE ) :: psi, evc, e, aux, hc, sc, vc, en
  !
  IF ( npol == 1 ) THEN
     !
     kdim = npw
     kdmx = npwx
     !
  ELSE
     !
     kdim = npwx*npol
     kdmx = npwx*npol
     !
  END IF
  !

  ALLOCATE( aux(kdmx, nstart ) )    
  ALLOCATE( hc( nstart, nstart) )    
  ALLOCATE( sc( nstart, nstart) )    
  ALLOCATE( vc( nstart, nstart) )    
  ALLOCATE( en( nstart ) )

  ALLOCATE( aux_d(kdmx, nstart ) )
  ALLOCATE( hc_d( nstart, nstart) )
  ALLOCATE( sc_d( nstart, nstart) )
  ALLOCATE( vc_d( nstart, nstart) )
  ALLOCATE( en_d( nstart ) )

  !
  ! ... Set up the Hamiltonian and Overlap matrix on the subspace :
  !
  ! ...      H_ij = <psi_i| H |psi_j>     S_ij = <psi_i| S |psi_j>
  !
  CALL h_psi( npwx, npw, nstart, psi_d, aux_d )
  !
  !call ZGEMM( 'C', 'N', nstart, nstart, kdim, ( 1.D0, 0.D0 ), psi, kdmx,  aux, kdmx, ( 0.D0, 0.D0 ), hc, nstart )
  call cublasZGEMM( 'C', 'N', nstart, nstart, kdim, ( 1.D0, 0.D0 ), psi_d, kdmx,  aux_d, kdmx, ( 0.D0, 0.D0 ), hc_d, nstart )
  !
!#ifndef USE_GPU_MPI
#if 1
  hc = hc_d            
  CALL mp_sum(  hc , intra_bgrp_comm )
  hc_d = hc
#else
  CALL mp_sum( hc_d, intra_bgrp_comm )
#endif
  !
  IF ( overlap ) THEN
     !
     CALL s_psi( npwx, npw, nstart, psi_d, aux_d )
     !
     !CALL ZGEMM( 'C', 'N', nstart, nstart, kdim, ( 1.D0, 0.D0 ), psi, kdmx,  aux, kdmx, ( 0.D0, 0.D0 ), sc, nstart )
     CALL cublasZGEMM( 'C', 'N', nstart, nstart, kdim, ( 1.D0, 0.D0 ), psi_d, kdmx,  aux_d, kdmx, ( 0.D0, 0.D0 ), sc_d, nstart )
     !
  ELSE
     !
     !CALL ZGEMM( 'C', 'N', nstart, nstart, kdim, ( 1.D0, 0.D0 ), psi, kdmx, psi, kdmx, ( 0.D0, 0.D0 ), sc, nstart )
     CALL cublasZGEMM( 'C', 'N', nstart, nstart, kdim, ( 1.D0, 0.D0 ), psi_d, kdmx, psi_d, kdmx, ( 0.D0, 0.D0 ), sc_d, nstart )
     !  
  END IF
  !
!#ifndef USE_GPU_MPI
#if 1
  sc = sc_d
  CALL mp_sum(  sc , intra_bgrp_comm )
  sc_d = sc
#else
  CALL mp_sum( sc_d, intra_bgrp_comm )
#endif
  !
  ! ... Diagonalize
  !
  CALL cdiaghg_gpu( nstart, nbnd, hc, hc_d, sc, sc_d, nstart, en, en_d, vc, vc_d )
  !
  e(:) = en_d(1:nbnd)
  e_d = e
  !
  ! ...  update the basis set
  !  
  !CALL ZGEMM( 'N', 'N', kdim, nbnd, nstart, ( 1.D0, 0.D0 ), psi, kdmx, vc, nstart, ( 0.D0, 0.D0 ), aux, kdmx )
  CALL cublasZGEMM( 'N', 'N', kdim, nbnd, nstart, ( 1.D0, 0.D0 ), psi_d, kdmx, vc_d, nstart, ( 0.D0, 0.D0 ), aux_d, kdmx )
  !     
  evc(:,:) = aux_d(:,1:nbnd)
  evc_d = evc
  !
  DEALLOCATE( en )
  DEALLOCATE( vc )
  DEALLOCATE( sc )
  DEALLOCATE( hc )
  DEALLOCATE( aux )

  DEALLOCATE( en_d )
  DEALLOCATE( vc_d )
  DEALLOCATE( sc_d )
  DEALLOCATE( hc_d )
  DEALLOCATE( aux_d )

  !
  RETURN
  !
END SUBROUTINE rotate_wfc_k_gpu
!
#endif
!
!----------------------------------------------------------------------------
SUBROUTINE protate_wfc_k( npwx, npw, nstart, nbnd, npol, psi, overlap, evc, e )
  !----------------------------------------------------------------------------
  !
  ! ... Parallel version of rotate_wfc for colinear, k-point calculations
  ! ... Subroutine with distributed matrices, written by Carlo Cavazzoni
  !
  USE kinds,            ONLY : DP
  USE mp_bands,         ONLY : intra_bgrp_comm, nbgrp
  USE mp_diag,          ONLY : ortho_comm, np_ortho, me_ortho, ortho_comm_id,&
                               leg_ortho, ortho_parent_comm, ortho_cntx
  USE descriptors,      ONLY : descla_init, la_descriptor
  USE parallel_toolkit, ONLY : zsqmher
  USE mp,               ONLY : mp_bcast, mp_root_sum, mp_sum, mp_barrier
  USE cpu_gpu_interface
  !
  IMPLICIT NONE
  !
  ! ... I/O variables
  !
  INTEGER :: npw, npwx, nstart, nbnd, npol
    ! dimension of the matrix to be diagonalized
    ! leading dimension of matrix psi, as declared in the calling pgm unit
    ! input number of states
    ! output number of states
    ! number of spin polarizations
  LOGICAL :: overlap
    ! if .FALSE. : S|psi> not needed
  COMPLEX(DP) :: psi(npwx*npol,nstart), evc(npwx*npol,nbnd)
    ! input and output eigenvectors (may overlap)
  REAL(DP) :: e(nbnd)
    ! eigenvalues
  !
  ! ... local variables
  !
  INTEGER :: kdim, kdmx
  COMPLEX(DP), ALLOCATABLE :: aux(:,:), hc(:,:), sc(:,:), vc(:,:)
  REAL(DP),    ALLOCATABLE :: en(:)
  !
  TYPE(la_descriptor) :: desc
    ! matrix distribution descriptors
  INTEGER :: nx
    ! maximum local block dimension
  LOGICAL :: la_proc
    ! flag to distinguish procs involved in linear algebra
  TYPE(la_descriptor), ALLOCATABLE :: desc_ip( :, : )
  INTEGER, ALLOCATABLE :: rank_ip( :, : )
  !
  ALLOCATE( desc_ip( np_ortho(1), np_ortho(2) ) )
  ALLOCATE( rank_ip( np_ortho(1), np_ortho(2) ) )
  !
  CALL desc_init( nstart, desc, desc_ip )
  !
  IF ( npol == 1 ) THEN
     !
     kdim = npw
     kdmx = npwx
     !
  ELSE
     !
     kdim = npwx*npol
     kdmx = npwx*npol
     !
  END IF
  !
  ALLOCATE( aux(kdmx, nstart ) )    
  ALLOCATE( hc( nx, nx) )    
  ALLOCATE( sc( nx, nx) )    
  ALLOCATE( vc( nx, nx) )    
  ALLOCATE( en( nstart ) )

  aux=(0.0_DP,0.0_DP)
  !
  ! ... Set up the Hamiltonian and Overlap matrix on the subspace :
  !
  ! ...      H_ij = <psi_i| H |psi_j>     S_ij = <psi_i| S |psi_j>
  !
  CALL h_psi( npwx, npw, nstart, psi, aux )
  !
  CALL compute_distmat( hc, psi, aux ) 
  !            
  IF ( overlap ) THEN
     !
     CALL s_psi( npwx, npw, nstart, psi, aux )
     !
     CALL compute_distmat( sc, psi, aux )
     !
  ELSE
     !
     CALL compute_distmat( sc, psi, psi )
     !  
  END IF
  !
  ! ... Diagonalize
  !
  CALL pcdiaghg( nstart, hc, sc, nx, en, vc, desc )
  !
  e(:) = en(1:nbnd)
  !
  ! ...  update the basis set
  !  
  CALL refresh_evc()
  !     
  evc(:,:) = aux(:,1:nbnd)
  !
  DEALLOCATE( en )
  DEALLOCATE( vc )
  DEALLOCATE( sc )
  DEALLOCATE( hc )
  DEALLOCATE( aux )
  !
  DEALLOCATE( desc_ip )
  DEALLOCATE( rank_ip )
  !
  RETURN
  !
  !
CONTAINS
  !
  SUBROUTINE desc_init( nsiz, desc, desc_ip )
     !
     INTEGER, INTENT(IN)  :: nsiz
     TYPE(la_descriptor), INTENT(OUT) :: desc
     TYPE(la_descriptor), INTENT(OUT) :: desc_ip(:,:)
     INTEGER :: i, j, rank
     INTEGER :: coor_ip( 2 )
     !
     CALL descla_init( desc, nsiz, nsiz, np_ortho, me_ortho, ortho_comm, ortho_cntx, ortho_comm_id )
     !
     nx = desc%nrcx
     !
     DO j = 0, desc%npc - 1
        DO i = 0, desc%npr - 1
           coor_ip( 1 ) = i
           coor_ip( 2 ) = j
           CALL descla_init( desc_ip(i+1,j+1), desc%n, desc%nx, &
                             np_ortho, coor_ip, ortho_comm, ortho_cntx, 1 )
           CALL GRID2D_RANK( 'R', desc%npr, desc%npc, i, j, rank )
           rank_ip( i+1, j+1 ) = rank * leg_ortho
        END DO
     END DO
     !
     la_proc = .FALSE.
     IF( desc%active_node > 0 ) la_proc = .TRUE.
     !
     RETURN
  END SUBROUTINE desc_init
  !
  !
  SUBROUTINE compute_distmat( dm, v, w )
     !
     !  This subroutine compute <vi|wj> and store the
     !  result in distributed matrix dm 
     !
     INTEGER :: ipc, ipr
     INTEGER :: nr, nc, ir, ic, root
     COMPLEX(DP), INTENT(OUT) :: dm( :, : )
     COMPLEX(DP) :: v(:,:), w(:,:)
     COMPLEX(DP), ALLOCATABLE :: work( :, : )
     !
     ALLOCATE( work( nx, nx ) )
     !
     work = ( 0.0_DP, 0.0_DP )
     !
     DO ipc = 1, desc%npc !  loop on column procs 
        !
        nc = desc_ip( 1, ipc )%nc
        ic = desc_ip( 1, ipc )%ic
        !
        DO ipr = 1, ipc ! desc%npr ! ipc ! use symmetry for the loop on row procs
           !
           nr = desc_ip( ipr, ipc )%nr
           ir = desc_ip( ipr, ipc )%ir
           !
           !  rank of the processor for which this block (ipr,ipc) is destinated
           !
           root = rank_ip( ipr, ipc )

           ! use blas subs. on the matrix block

           CALL ZGEMM( 'C', 'N', nr, nc, kdim, ( 1.D0, 0.D0 ) ,  v(1,ir), kdmx, w(1,ic), kdmx, ( 0.D0, 0.D0 ), work, nx )

           ! accumulate result on dm of root proc.
           CALL mp_root_sum( work, dm, root, ortho_parent_comm )

        END DO
        !
     END DO
     if (ortho_parent_comm.ne.intra_bgrp_comm .and. nbgrp > 1) dm = dm/nbgrp
     !
     CALL zsqmher( nstart, dm, nx, desc )
     !
     DEALLOCATE( work )
     !
     RETURN
  END SUBROUTINE compute_distmat


  SUBROUTINE refresh_evc( )
     !
     INTEGER :: ipc, ipr
     INTEGER :: nr, nc, ir, ic, root
     COMPLEX(DP), ALLOCATABLE :: vtmp( :, : )
     COMPLEX(DP) :: beta

     ALLOCATE( vtmp( nx, nx ) )
     !
     DO ipc = 1, desc%npc
        !
        nc = desc_ip( 1, ipc )%nc
        ic = desc_ip( 1, ipc )%ic
        !
        IF( ic <= nbnd ) THEN
           !
           nc = min( nc, nbnd - ic + 1 )
           !
           beta = ( 0.D0, 0.D0 )

           DO ipr = 1, desc%npr
              !
              nr = desc_ip( ipr, ipc )%nr
              ir = desc_ip( ipr, ipc )%ir
              !
              root = rank_ip( ipr, ipc )

              IF( ipr-1 == desc%myr .AND. ipc-1 == desc%myc .AND. la_proc ) THEN
                 !
                 !  this proc sends his block
                 ! 
                 CALL mp_bcast( vc(:,1:nc), root, ortho_parent_comm )
                 CALL ZGEMM( 'N', 'N', kdim, nc, nr, ( 1.D0, 0.D0 ),  psi(1,ir), kdmx, vc, nx, beta, aux(1,ic), kdmx )
              ELSE
                 !
                 !  all other procs receive
                 ! 
                 CALL mp_bcast( vtmp(:,1:nc), root, ortho_parent_comm )
                 CALL ZGEMM( 'N', 'N', kdim, nc, nr, ( 1.D0, 0.D0 ),  psi(1,ir), kdmx, vtmp, nx, beta, aux(1,ic), kdmx )
              END IF
              ! 

              beta = ( 1.D0, 0.D0 )

           END DO
           !
        END IF
        !
     END DO
     !
     DEALLOCATE( vtmp )

     RETURN
  END SUBROUTINE refresh_evc

END SUBROUTINE protate_wfc_k
