!
! Copyright (C) 2001 PWSCF group
! This file is distributed under the terms of the
! GNU General Public License. See the file `License'
! in the root directory of the present distribution,
! or http://www.gnu.org/copyleft/gpl.txt .
!

subroutine delta_e (nr1, nr2, nr3, nrxx, rho, v_in, v_out, omega, &
     de, deband, nspin)
  use parameters
  implicit none

  integer :: nspin, nr1, nr2, nr3, nrxx, i
  ! nspin=1 if LDA, nspin=2 if LSDA
  ! fft grid dimensions
  ! counter

  real(kind=DP) :: rho (nrxx, nspin), v_in (nrxx, nspin), v_out (nrxx, &
       nspin), omega, de, deband
  ! charge density
  ! in and ...
  ! ... out potentials from potential mixing
  ! cell volume
  ! total energy and band energy corrections

  de = 0.d0
  deband = 0.d0
  if (nspin.eq.1) then
     !
     ! spin-unpolarized case
     !
     do i = 1, nrxx
        de     = de + rho(i,nspin) * ( v_out(i,1) - v_in(i,1) )
        deband = deband - rho(i,nspin) * v_in(i,1)
     enddo
  else
     !
     ! spin-polarized case
     !
     do i = 1, nrxx
        de     = de + rho(i,1) * ( v_out(i,1) - v_in(i,1) ) + &
             rho(i,2) * ( v_out(i,2) - v_in(i,2) )
        deband = deband - rho(i,1) * v_in(i,1) - rho(i,2) * v_in(i,2)
     enddo

  endif

  de = omega * de / (nr1 * nr2 * nr3)
  deband = omega * deband / (nr1 * nr2 * nr3)

#ifdef __PARA
  call reduce (1, de)
  call reduce (1, deband)
#endif

  return

end subroutine delta_e
