module sdar_group
!
! this module contains everything to identify
! and integrate regularized groups...
!
! :References: Makino et Aarseth 2002,Wang et al. 2020, Wang et al. 2021, Rantala et al. 2023
!
! :Owner: Daniel Price
!
 use utils_sdar
 implicit none
 public :: group_identify
 public :: evolve_groups
 ! parameters for group identification
 real, public :: r_neigh  = 0.0
 real, public :: t_crit   = 0.0
 real, public :: C_bin    = 0.0
 real, public :: r_search = 0.0
 private
contains

!-----------------------------------------------
!
! Group identification routines
!
!-----------------------------------------------
subroutine group_identify(nptmass,xyzmh_ptmass,vxyz_ptmass,group_info,nmatrix)
 real,    intent(in)               :: xyzmh_ptmass(:,:),vxyz_ptmass(:,:)
 integer, intent(in)               :: group_info(:,:)
 integer(kind=1), intent(inout)    :: nmatrix(:,:)
 integer, intent(in) :: nptmass

 ngroup = 0
 n_ingroup = 0
 n_sing = 0
 call matrix_construction(xyzmh_ptmass,vxyz_ptmass,nmatrix,nptmass)
 call form_group(group_info,nmatrix,nptmass)

end subroutine group_identify


subroutine form_group(group_info,nmatrix,nptmass)
 use part, only : igid,igarg,igsize,igcum
 integer(kind=1), intent(in) :: nmatrix(:,:)
 integer, intent(out):: group_info(:,:)
 integer, intent(in) :: nptmass
 integer :: i
 logical :: visited(nptmass)
 do i=1,nptmass
    if(.not.visited(i)) then
       n_ingroup = n_ingroup + 1
       call dfs(i,i,visited,group_info,nmatrix,nptmass,n_ingroup)
       if (group_info(igsize,i)>1)then
          ngroup = ngroup + 1
          group_info(igcum,ngroup+1) = group_info(igsize,i) + group_info(igcum,ngroup)
       else
          n_ingroup= n_ingroup - 1
          group_info(igsize,i) = 0
          group_info(igarg,nptmass-n_sing) = i
          group_info(igid,nptmass-n_sing) = 0
          n_sing = n_sing + 1
       endif
    endif
 enddo
end subroutine form_group

recursive subroutine dfs(inode,iroot,visited,group_info,nmatrix,npt,n_ingroup)
 use part, only : igid,igarg,igsize,igcum
 integer, intent(in) :: inode,npt,iroot
 integer(kind=1), intent(in) :: nmatrix(:,:)
 integer, intent(inout) :: group_info(:,:)
 integer, intent(inout) :: n_ingroup
 logical, intent(inout) :: visited(:)
 integer :: j
 !print*,nping,inode
 group_info(igarg,n_ingroup) = inode
 group_info(igid,n_ingroup) = iroot
 group_info(igsize,iroot) = group_info(igsize,iroot)+1
 visited(inode) = .true.
 do j=1,npt
    if (nmatrix(inode,j)==1 .and. (visited(j).eqv..false.)) then
       n_ingroup = n_ingroup + 1
       call dfs(j,iroot,visited,group_info,nmatrix,npt,n_ingroup)
    endif
 enddo
end subroutine dfs


subroutine matrix_construction(xyzmh_ptmass,vxyz_ptmass,nmatrix,nptmass)
 use utils_kepler, only: bindE,extract_a,extract_e,extract_ea
 integer(kind=1), intent(out):: nmatrix(:,:)
 real,    intent(in) :: xyzmh_ptmass(:,:)
 real,    intent(in) :: vxyz_ptmass(:,:)
 integer, intent(in) :: nptmass
 real :: xi,yi,zi,vxi,vyi,vzi,mi
 real :: dx,dy,dz,dvx,dvy,dvz,r2,r,v2,mu
 real :: aij,eij,B,rperi
 integer :: i,j

 nmatrix = 0.

 do i=1,nptmass
    xi = xyzmh_ptmass(1,i)
    yi = xyzmh_ptmass(2,i)
    zi = xyzmh_ptmass(3,i)
    mi = xyzmh_ptmass(4,i)
    vxi = vxyz_ptmass(1,i)
    vyi = vxyz_ptmass(2,i)
    vzi = vxyz_ptmass(3,i)
    do j=1,nptmass
       if(i==j) cycle
       if(j>i) then
          dx = xi - xyzmh_ptmass(1,j)
          dy = yi - xyzmh_ptmass(2,j)
          dz = zi - xyzmh_ptmass(3,j)
          r2 = dx**2+dy**2+dz**2
          r = sqrt(r2)
          if (r<r_neigh) then
             nmatrix(i,j) = 1
             cycle
          else if (r>r_search) then
             nmatrix(i,j) = 0
             cycle
          endif
          mu = mi + xyzmh_ptmass(4,j)
          dvx = vxi - vxyz_ptmass(1,j)
          dvy = vyi - vxyz_ptmass(2,j)
          dvz = vzi - vxyz_ptmass(3,j)
          v2 = dvx**2+dvy**2+dvz**2
          call bindE(v2,r,mu,B)
          call extract_a(r,mu,v2,aij)
          if (B<0) then
             if (aij<r_neigh) then
                nmatrix(i,j) = 1
             endif
          else
             call extract_e(dx,dy,dz,dvx,dvy,dvz,mu,r,eij)
             rperi = aij*(1-eij)
             if (rperi<r_neigh .and. C_bin*(r2/v2)<t_crit) then
                nmatrix(i,j) = 1
             endif
          endif
       else
          nmatrix(i,j) = nmatrix(j,i)
       endif
    enddo
 enddo
end subroutine matrix_construction

!---------------------------------------------
!
! Routines needed to integrate subgroups
!
!---------------------------------------------

subroutine evolve_groups(n_group,tnext,group_info,xyzmh_ptmass,vxyz_ptmass,fxyz_ptmass,gtgrad)
 use part, only: igid,igarg,igsize,igcum
 real,    intent(inout) :: xyzmh_ptmass(:,:),vxyz_ptmass(:,:),fxyz_ptmass(:,:),gtgrad(:,:)
 integer, intent(in)    :: group_info(:,:)
 integer, intent(inout) :: n_group
 real,    intent(in)    :: tnext
 integer :: i,j,start_id,end_id,gsize
 real :: W,tcoord
 !$omp parallel do default(none)&
 !$omp shared(xyzmh_ptmass,vxyz_ptmass,fxyz_ptmass)&
 !$omp shared(tnext)&
 !$omp private(i,j,start_id,end_id,gsize,W,tcoord)&
 do i=1,n_group
    start_id = group_info(igcum,i) + 1
    end_id   = group_info(igcum,i+1)
    gsize    = end_id - start_id
    call integrate_to_time(xyzmh_ptmass,vxyz_ptmass,fxyz_ptmass,gtgrad)
 enddo


end subroutine evolve_groups

subroutine integrate_to_time(start_id,end_id,gsize,ds_init,xyzmh_ptmass,vxyz_ptmass,fxyz_ptmass,gtgrad)
 real, intent(inout) :: xyzmh_ptmass(:,:),vxyz_ptmass(:,:), &
                        fxyz_ptmass(:,:),gtgrad(:,:)
 integer, intent(in) :: start_id,end_id,gsize
 real,    intent(in) :: ds_init
 real    :: ds(2)
 real    :: timetable(ck_size)
 integer :: switch
 integer :: step_count_int,step_count_tsyn,n_step_end
 real    :: dt,dt_end,step_modif,t_old,W_old
 logical :: t_end_flag,backup_flag
 integer :: i

 step_count_int  = 0
 step_count_tsyn = 0
 n_step_end = 0
 t_end_flag = .false.
 backup_flag = .true.
 ds = ds_init
 switch = 1

 do while (.true.)

    if (backup_flag) then
       call backup_data(gsize,xyzmh_ptmass,vxyz_ptmass,bdata)
    else
       call restore_state(gsize,xyzmh_ptmass,vxyz_ptmass,tcoord,t_old,W,W_old,bdata)
    endif
    t_old = tcoord
    W_old = W
    if (gsize>1) then
       do i=1,ck_size
          call drift_TTL (gsize,xyzmh_ptmass,vxyz_ptmass,ds(switch)*ck(i), &
                          tcoord,W,start_id,end_id)
          time_table(i) = tcoord
          call kick_TTL  (gsize,xyzmh_ptmass,vxyz_ptmass,fxyz,gtgrad, &
                          ds(switch)*dk(i),W,om,start_id,end_id)
       enddo
    else
       call oneStep_bin(gsize,xyzmh_ptmass,vxyz_ptmass,fxyz,gtgrad, &
                        ds(switch),tcoord,W,om,time_table,start_id,end_id)
    endif
    dt = tcoord - t_old

    step_count_int = step_count_int + 1

    if(step_count_int > max_step) then
       print*,"MAX STEP NUMBER, ABORT !!!"
       call abort
    endif

    if ((.not.t_end_flag).and.(dt<0.)) then
       !print*,"neg dt !!!",tnext,dt
       call regularstepfactor((abs(tnext/dt))**(1./6.),step_modif)
       step_modif = min(max(step_modif,0.0625),0.5)
       ds(switch) = ds(switch)*step_modif
       ds(3-switch) = ds(switch)

       backup_flag = .false.
       continue
    endif

    if (tcoord < tnext - time_error) then
       if (t_end_flag .and. (ds(switch)==ds(3-switch))) then
          step_count_tsyn = step_count_tsyn + 1
          dt_end = tnext - tcoord
          if (dt<0.) then
             call regularstepfactor((abs(tnext/dt))**(1./6.),step_modif)
             step_modif = min(max(step_modif,0.0625),0.5)
             ds(switch)   = ds(switch)*step_modif
             ds(3-switch) = ds(switch)
          else if ((n_step_end > 1) .and. (dt<0.3*dt_end)) then
             ds(3-switch) = ds(switch) * dt_end/dt
          else
             n_step_end = n_step_end + 1
          endif
       endif
       ds(switch) = ds(3-switch)
       switch = 3 - switch
       if (dt>0) then
          backup_flag = .true.
       else
          backup_flag  = .false.
       endif

    else if (tcoord > tnext + time_error) then
       t_end_flag = .true.
       backup_flag = .false.
       n_step_end = 0
       step_count_tsyn = step_count_tsyn + 1

       call new_ds_sync_sup(ds,time_table,tnext,switch)
    else
       exit
    endif
 enddo

end subroutine integrate_to_time


subroutine regularstepfactor(fac_in,fac_out)
 real, intent(in) :: fac_in
 real, intent(out):: fac_out
 fac_out = 1.0
 if (fac_in<1) then
    do while (fac_out>fac_in)
       fac_out = fac_out*0.5
    enddo
 else
    do while(fac_out<=fac_in)
       fac_out = fac_out *2
    enddo
    fac_out = fac_out*0.5
 endif
end subroutine regularstepfactor

subroutine new_ds_sync_sup(ds,time_table,tnext,switch)
 real,    intent(inout) :: ds(:)
 real,    intent(in)    :: time_table(:)
 real,    intent(in)    :: tnext
 integer, intent(in)    :: switch
 integer :: i,k
 real :: tp,dtk,dstmp
 do i=1,ck_size
    k = cck_sorted_id(i)
    if(tnext<time_table(k)) exit
 enddo

 if (i==1) then
    ds(switch) = ds(switch)*cck_sorted(i)*(tnext/time_table(k))
    ds(3-switch) = ds(switch)

 else
    tp  = time_table(cck_sorted_id(i-1))
    dtk = time_table(k)-tp
    dstmp = ds(switch)
    ds(switch) = ds(switch)*cck_sorted(i-1)
    ds(3-switch) = dstmp*(cck_sorted(i)-cck_sorted(i-1))*min(1.0,(tnext-tp+time_error)/dtk)
 endif

end subroutine new_ds_sync_sup




subroutine backup_data(gsize,xyzmh_ptmass,vxyz_ptmass,bdata)
 real, intent(in) ::xyzmh_ptmass(:,:),vxyz_ptmass(:,:)
 real, intent(out)::bdata(:)
 integer,intent(in) :: gsize
 integer :: i,j
 do i=1,gsize
    do j=1,ndim
       bdata(j,i) = xyzmh_ptmass(j,i)
       bdata(j+ndim,i) =,vxyz_ptmass(j,i)
    enddo
    !print*,bdata(1,:)
 enddo

end subroutine backup_data


subroutine restore_state(gsize,xyzmh_ptmass,vxyz_ptmass,tcoord,t_old,W,W_old,bdata)
 real, intent(inout) ::xyzmh_ptmass(:,:),vxyz_ptmass(:,:)
 real, intent(out) :: tcoord,W
 real, intent(in)  :: t_old,W_old
 real, intent(in)::bdata
 integer, intent(in) :: gsize
 integer :: i,j
 do i=1,gsize
    do j=1,ndim
       xyzmh_ptmass(j,i) = bdata(j,i)
       vxyz_ptmass(j,i) = bdata(j+ndim,i)
    enddo
    tcoord   = t_old
    W = W_old
 enddo

end subroutine restore_state


subroutine drift_TTL(tcoord,W,h,xyzmh_ptmass,vxyz_ptmass,s_id,e_id)
 real, intent(inout) :: xyzmh_ptmass(:,:),vxyz_ptmass(:,:)
 real, intent(inout) :: tcoord
 real, intent(in)    :: h,W
 integer,intent(in)  :: s_id,e_id

 real :: dtd

 dtd = h/W

 tcoord = tcoord + dtd

 do i=s_id,e_id
    xyzmh_ptmass(1,i) = xyzmh_ptmass(1,i) + dtd*vxyz_ptmass(1,i)
    xyzmh_ptmass(2,i) = xyzmh_ptmass(2,i) + dtd*vxyz_ptmass(2,i)
    xyzmh_ptmass(3,i) = xyzmh_ptmass(3,i) + dtd*vxyz_ptmass(3,i)
 enddo

end subroutine drift_TTL

subroutine kick_TTL(h,W,xyzmh_ptmass,vxyz_ptmass,fxyz_ptmass,gtgrad,s_id,e_id)
 real, intent(inout) :: xyzmh_ptmass(:,:),vxyz_ptmass(:,:),fxyz_ptmass(:,:),gtgrad(:,:)
 real, intent(in)    :: h
 real, intent(inout) :: W
 integer,intent(in)  :: s_id,e_id
 real :: om,dw,dt
 integer :: i

 call get_force_TTL(xyzmh_ptmass,om,fxyz_ptmass,gtgrad,s_id,e_id)


 dtk = h/om
 do i=s_id,e_id
    vxyz_ptmass(1,i) = vxyz_ptmass(1,i) + (0.5*dtk)*fxyz_ptmass(1,i)
    vxyz_ptmass(2,i) = vxyz_ptmass(2,i) + (0.5*dtk)*fxyz_ptmass(2,i)
    vxyz_ptmass(3,i) = vxyz_ptmass(3,i) + (0.5*dtk)*fxyz_ptmass(3,i)
 enddo

 dw = 0.
 do i=s_id,e_id
    dw = dw + vxyz_ptmass(1,i)*gtgrad(1,i) + &
              vxyz_ptmass(2,i)*gtgrad(2,i) + &
              vxyz_ptmass(3,i)*gtgrad(3,i)
 enddo

 W = W + dw*dtk

 do i=s_id,e_id
    vxyz_ptmass(1,i) = vxyz_ptmass(1,i) + (0.5*dtk)*fxyz_ptmass(1,i)
    vxyz_ptmass(2,i) = vxyz_ptmass(2,i) + (0.5*dtk)*fxyz_ptmass(2,i)
    vxyz_ptmass(3,i) = vxyz_ptmass(3,i) + (0.5*dtk)*fxyz_ptmass(3,i)
 enddo


end subroutine kick_TTL

subroutine oneStep_bin(gsize,xyzmh_ptmass,vxyz_ptmass,fxyz_ptmass,gtgrad,ds,tcoord,W,om,time_table,s_id,e_id)
 use force, only:get_force_TTL
 real, intent(inout) :: xyzmh_ptmass(:,:),vxyz_ptmass(:,:),fxyz_ptmass(:,:),gtgrad(:,:),time_table(:)
 real, intent(in)    :: ds
 real, intent(inout) :: tcoord,W,om
 integer, intent(in) :: s_id,e_id,gsize
 integer :: i
 real :: dtd,dtk,dvel1(3),dvel2(3),dw

 dtd = ds*ck(i)/W
 tcoord = tcoord + dtd
 time_table(i) = tcoord

 xyzmh_ptmass(1,s_id) = xyzmh_ptmass(1,s_id) + dtd*vxyz_ptmass(1,s_id)
 xyzmh_ptmass(2,s_id) = xyzmh_ptmass(2,s_id) + dtd*vxyz_ptmass(2,s_id)
 xyzmh_ptmass(3,s_id) = xyzmh_ptmass(3,s_id) + dtd*vxyz_ptmass(3,s_id)
 xyzmh_ptmass(1,e_id) = xyzmh_ptmass(1,e_id) + dtd*vxyz_ptmass(1,e_id)
 xyzmh_ptmass(2,e_id) = xyzmh_ptmass(2,e_id) + dtd*vxyz_ptmass(2,e_id)
 xyzmh_ptmass(3,e_id) = xyzmh_ptmass(3,e_id) + dtd*vxyz_ptmass(3,e_id)

 call get_force_TTL(fxyz_ptmass,om,gtgrad,xyzmh_ptmass,start_id,end_id)

 dtk = ds*dk(i)/om

 dvel1(1) = 0.5*dtk*fxyz_ptmass(1,s_id)
 dvel1(2) = 0.5*dtk*fxyz_ptmass(2,s_id)
 dvel1(3) = 0.5*dtk*fxyz_ptmass(3,s_id)
 dvel2(1) = 0.5*dtk*fxyz_ptmass(1,e_id)
 dvel2(2) = 0.5*dtk*fxyz_ptmass(2,e_id)
 dvel2(3) = 0.5*dtk*fxyz_ptmass(3,e_id)

 vxyz_ptmass(1,s_id) = vxyz_ptmass(1,s_id) + dvel1(1)
 vxyz_ptmass(2,s_id) = vxyz_ptmass(2,s_id) + dvel1(2)
 vxyz_ptmass(3,s_id) = vxyz_ptmass(3,s_id) + dvel1(3)
 vxyz_ptmass(1,e_id) = vxyz_ptmass(1,e_id) + dvel2(1)
 vxyz_ptmass(2,e_id) = vxyz_ptmass(2,e_id) + dvel2(2)
 vxyz_ptmass(3,e_id) = vxyz_ptmass(3,e_id) + dvel2(3)

 dw = gtgrad(1,s_id)*vxyz_ptmass(1,s_id)+&
         gtgrad(2,s_id)*vxyz_ptmass(2,s_id)+&
         gtgrad(3,s_id)*vxyz_ptmass(3,s_id)+&
         gtgrad(1,e_id)*vxyz_ptmass(1,e_id)+&
         gtgrad(2,e_id)*vxyz_ptmass(2,e_id)+&
         gtgrad(3,e_id)*vxyz_ptmass(3,e_id)

 W = W + dw*dtk

 vxyz_ptmass(1,s_id) = vxyz_ptmass(1,s_id) + dvel1(1)
 vxyz_ptmass(2,s_id) = vxyz_ptmass(2,s_id) + dvel1(2)
 vxyz_ptmass(3,s_id) = vxyz_ptmass(3,s_id) + dvel1(3)
 vxyz_ptmass(1,e_id) = vxyz_ptmass(1,e_id) + dvel2(1)
 vxyz_ptmass(2,e_id) = vxyz_ptmass(2,e_id) + dvel2(2)
 vxyz_ptmass(3,e_id) = vxyz_ptmass(3,e_id) + dvel2(3)


end subroutine oneStep_bin


subroutine get_force_TTL(xyzmh_ptmass,om,fxyz_ptmass,gtgrad,s_id,e_id)
 real, intent(in)    :: xyzmh_ptmass(:,:)
 real, intent(inout) :: fxyz_ptmass(:,:),gtgrad(:,:)
 real, intent(out)   :: om
 integer, intent(in) :: s_id,e_id
 real    :: mi,mj,xi,yi,zi,dx,dy,dz,r2
 real    :: gravf,gtki
 integer :: i,j
 om = 0.
 do i=s_id,e_id
    fxyz_ptmass(1,i) = 0.
    fxyz_ptmass(2,i) = 0.
    fxyz_ptmass(3,i) = 0.
    gtgrad(1,i) = 0.
    gtgrad(2,i) = 0.
    gtgrad(3,i) = 0.
 enddo

 do i=s_id,e_id
    gtki = 0.
    xi = xyzmh_ptmass(1,j)
    yi = xyzmh_ptmass(2,j)
    zi = xyzmh_ptmass(3,j)
    mi = xyzmh_ptmass(4,j)
    do j=s_id,e_id
       if (i==j) cycle
       dx = xi - xyzmh_ptmass(1,j)
       dy = yi - xyzmh_ptmass(2,j)
       dz = zi - xyzmh_ptmass(3,j)
       r2 = dx**2+dy**2+dz**3
       r  = sqrt(r)
       mj = xyzmh_ptmass(4,j)
       gravf = xyzmh_ptmass(4,j)*(1./r2*r)
       gtki  = gtki + mj*(1./r)
       fxyz_ptmass(1,i) = fxyz_ptmass(1,i) + dx*gravf
       fxyz_ptmass(2,i) = fxyz_ptmass(2,i) + dy*gravf
       fxyz_ptmass(3,i) = fxyz_ptmass(3,i) + dz*gravf
       gtgrad(1,i) = gtgrad(1,i) + dx*gravf*mi
       gtgrad(2,i) = gtgrad(2,i) + dy*gravf*mi
       gtgrad(3,i) = gtgrad(3,i) + dz*gravf*mi
    enddo
    om = om + gtki*m(i)
 enddo

 om = om*0.5

end subroutine get_force_TTL

subroutine initial_OM(xyzmh_ptmass,om,s_id,e_id)
 real, intent(in)    :: xyzmh_ptmass(:,:)
 real, intent(out)   :: om
 integer, intent(in) :: s_id,e_id
 integer :: i,j
 real    :: gtki,dx,dy,dz,xi,yi,zi,r1

 om = 0.

 do i=s_id,e_id
    gtki = 0.
    xi = xyzmh_ptmass(1,i)
    yi = xyzmh_ptmass(2,i)
    zi = xyzmh_ptmass(3,i)
    mi = xyzmh_ptmass(4,i)
    do j=s_id,e_id
       if (i == j) cycle
       dx = xi - xyzmh_ptmass(1,j)
       dy = yi - xyzmh_ptmass(2,j)
       dz = zi - xyzmh_ptmass(3,j)
       r1 = 1./sqrt(dx**2+dy**2+dz**2)
       gtki = gtki + xyzmh_ptmass(4,j)*r1
    enddo
    om = om + gtki*mi
 enddo

 om = om*0.5

end subroutine initial_OM

end module sdar_group
