normal_sign_x:
!byte 1,1,0,$ff,$ff,$ff,0,1
normal_sign_y:
!byte 0,1,1,1,0,$ff,$ff,$ff
normal_x_lo:
!byte 0,181,0,75,0,75,0,181
normal_x_hi:
!byte 1,0,0,$ff,$ff,$ff,0,0
normal_y_lo:
!byte 0,181,0,181,0,75,0,75
normal_y_hi:
!byte 0,0,1,0,0,$ff,$ff,$ff
; Halfway between normal codes c and c + 1 (22.5 + 45 * c degrees), scaled
; by 255/256 and truncated, so |n| < 1: the joint normal of a 135-degree
; corner touched on both faces at once.
joint_normal_x_lo:
!byte 235,97,<-97,<-235,<-235,<-97,97,235
joint_normal_x_hi:
!byte 0,0,$ff,$ff,$ff,$ff,0,0
joint_normal_y_lo:
!byte 97,235,235,97,<-97,<-235,<-235,<-97
joint_normal_y_hi:
!byte 0,0,0,0,$ff,$ff,$ff,$ff
