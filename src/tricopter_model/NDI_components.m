clear, clc
digits(4)
format short

syms Ixx_b Iyy_b Izz_b Ixy_b Ixz_b Iyz_b % Moments and products of inertia calculated about the BAC
syms Ixx Iyy Izz Ixy Ixz Iyz             % Moments and products of inertia calculated about the CG
syms P Q R Pd Qd Rd U V W Ud Vd Wd
syms m cx cy cz
syms X Y Z L M N
syms Gx Gy Gz Gl Gm Gn
syms mass

%% Tricopter specific variables
syms tau % Throttle for each input
syms eta gamma % eta: arm roll angle || gamma: arm pitch angle

% Rotation matrixes
syms ang
Rx = [1,    0,         0;
      0, cos(ang),   sin(ang);
      0, -sin(ang),  cos(ang)];

Ry = [cos(ang), 0, -sin(ang);
        0,      1,    0;
      sin(ang), 0, cos(ang)];
  
Rz = [cos(ang),  sin(ang), 0;
      -sin(ang), cos(ang), 0;
      0,         0,        1];
% Body to Earth
syms phi theta psi
R_E2B = subs(Rx, ang, phi) * subs (Ry, ang, theta) * subs (Rz, ang, psi);

% % Euler Rate Body to earth
% syms phi_dot theta_dot psi_dot
% L_E2B = [phi_dot, 0, 0].' +...
%          subs(Rx, ang, phi) * [0, theta_dot, 0].' +...
%          subs(Rx, ang, phi) * subs (Ry, ang, theta) * [0, 0, psi_dot].';

% Body to arm matrixes Varm = R_B2Arm * Vbody
R_BtoArm1 = subs (Ry, ang, gamma) * subs(Rx, ang, eta); % Rotation matrix Body2Arm1
R_BtoArm23 = subs (Rx, ang, gamma) * subs(Ry, ang, eta); % Rotation matrix Body2Arm1

%% Tricopter Forces/Moments(x) 9DOF
% To apply NDI to nonlinear systems
% x_dot = f(x) + g(x,u)
% Calculate g(x,u) --> gx

syms Kt Kq
% Kt = 19.5; % Thrust = Kt * tau || Previous used value: 15
% Kq = 0.26; % Moment = Kq * tau || Previous used value: 0.07

Tarm = [0 0 -Kt * tau].'; % Local arm thrust vector
Marm = [0 0 -Kq * tau].'; % Local arm moment vector for CW blade rotation

% Force and moment contributions from arms in body axis
syms tau1 tau2 tau3 % Throttle for each input
syms eta1 eta2 eta3 gamma1 gamma2 gamma3 % eta: arm roll angle || gamma: arm pitch angle
rot_sign1 = 1; rot_sign2 = -1; rot_sign3 = -1; % CW = 1 || CCW = -1
% TODO rot_sign should be defined in a header or init file

% Tbody_ext = R_Arm2Body * Tarm
Tarm1_body = subs(R_BtoArm1.',  [gamma, eta], [gamma1, eta1]) * subs(Tarm, tau, tau1);
Tarm2_body = subs(R_BtoArm23.', [gamma, eta], [gamma2, eta2]) * subs(Tarm, tau, tau2);
Tarm3_body = subs(R_BtoArm23.', [gamma, eta], [gamma3, eta3]) * subs(Tarm, tau, tau3);
Tbody_ext = Tarm1_body + Tarm2_body + Tarm3_body;
% External moments about BAC -> Mbody_ext = R_Arm2Body * Marm + r_arm x Tbody_ext
l = 0.3450; % Distance from BAC to arm
% Vector going from BAC to each of the arms.
r_arm1 = l*[1;0;0]; 
r_arm2 = l*[-1/2;sqrt(3)/2;0];
r_arm3 = l*[-1/2;-sqrt(3)/2;0];
Mbody_ext = subs(R_BtoArm1.',  [gamma, eta], [gamma1, eta1]) * rot_sign1 * subs(Marm, tau, tau1) +...
            subs(R_BtoArm23.', [gamma, eta], [gamma2, eta2]) * rot_sign2 * subs(Marm, tau, tau2) +...
            subs(R_BtoArm23.', [gamma, eta], [gamma3, eta3]) * rot_sign3 * subs(Marm, tau, tau3) +...
            cross(r_arm1, Tarm1_body)+...
            cross(r_arm2, Tarm2_body)+...
            cross(r_arm3, Tarm3_body);

gx = [Tbody_ext; Mbody_ext];

% Approximate gx = g(x,u) as
% g(x,u) ~= g(x,u0) + jac(g(x,u), u) * (u - u0)
% g(x,u) ~= h(x,u0) + jac(g(x,u), u) * u
J_gx = jacobian(gx, [tau1, eta1, gamma1, tau2, eta2, gamma2, tau3, eta3, gamma3]);

% Previus step / initial inputs - Needed for first order approximation
%    [tau1, tau2, tau3, gamma1, gamma2, gamma3, eta1, eta2, eta3]
syms tau1_0 tau2_0 tau3_0 gamma1_0 gamma2_0 gamma3_0 eta1_0 eta2_0 eta3_0
u0 = [tau1_0, eta1_0, gamma1_0, tau2_0, eta2_0, gamma2_0, tau3_0, eta3_0, gamma3_0].';
J_gx0 = subs(J_gx, [tau1, eta1, gamma1, tau2, eta2, gamma2, tau3, eta3, gamma3], u0.');
gx_u0 = subs(gx, [tau1, eta1, gamma1, tau2, eta2, gamma2, tau3, eta3, gamma3], u0.');

hx_u0 = gx_u0 - J_gx0 * u0;

%% Eq of motion (General)
% I_BAC * omega_dot + omega x (I_BAC * omega) = Ma + (Mc)u * U
%       Where I_BAC - Inertia moment about BAC
%             omega, omega_dot - Angular speed, acc
%             Ma - External moments due to the system state and perturbations ie. Gravity, Wind, etc...
%             (Mc)u * U - External moments created by actuators
% omega_dot  = I_BAC \ (Ma - omega x (I_BAC * omega)) + (I_BAC \ (Mc)u) * U
%
% Dynamics about BAC with Mass Properties (Moments and Product of Inertia) defined about the Centre of Gravity.
%             Udot Vdot Wdot   Pdot     Qdot     Rdot
mass_matrix= [mass   0    0      0     mass*cz -mass*cy ; % X
                0  mass   0  -mass*cz     0     mass*cx ; % Y
                0    0  mass  mass*cy -mass*cx     0    ; % Z
                0    0    0     Ixx     -Ixy     -Ixz   ; % L
                0    0    0    -Ixy      Iyy     -Iyz   ; % M
                0    0    0    -Ixz     -Iyz      Izz   ];% N       
% *******************************************************                      
excitation_matrix= [Gx + mass*R*V - mass*Q*W + mass*cx*(Q^2+R^2) - mass*cy*P*Q - mass*cz*P*R ; 
                    Gy - mass*R*U + mass*P*W - mass*cx*P*Q + mass*cy*(P^2+R^2) - mass*cz*Q*R ;
                    Gz + mass*Q*U - mass*P*V - mass*cx*P*R - mass*cy*Q*R + mass*cz*(P^2+Q^2) ;
                    - Q*R*(Izz-Iyy) - P*R*Ixy + P*Q*Ixz - (R^2-Q^2)*Iyz;
                    - P*R*(Ixx-Izz) + Q*R*Ixy - P*Q*Iyz - (P^2-R^2)*Ixz;
                    - P*Q*(Iyy-Ixx) - Q*R*Ixz + P*R*Iyz - (Q^2-P^2)*Ixy];
%                 Gravity term is being calculated twice and it cancels
%                 itself.
%                     Gl - Q*R*(Izz-Iyy) - P*R*Ixy + P*Q*Ixz - (R^2-Q^2)*Iyz + cz*Gy - cy*Gz;
%                     Gm - P*R*(Ixx-Izz) + Q*R*Ixy - P*Q*Iyz - (P^2-R^2)*Ixz + cx*Gz - cz*Gx;
%                     Gn - P*Q*(Iyy-Ixx) - Q*R*Ixz + P*R*Iyz - (Q^2-P^2)*Ixy + cy*Gx - cx*Gy];

% % Mass Properties (Moments and Product of Inertia) are defined about the Body Axis Centre.
% %             Udot      Vdot      Wdot       Pdot        Qdot        Rdot
% mass_matrix= [mass      0         0          0           mass*cz    -mass*cy ; % X
%               0         mass      0         -mass*cz     0           mass*cx ; % Y
%               0         0         mass       mass*cy    -mass*cx     0       ; % Z
%               0        -mass*cz   mass*cy    Ixx        -Ixy        -Ixz     ; % L
%               mass*cz   0        -mass*cx   -Ixy         Iyy        -Iyz     ; % M
%              -mass*cy   mass*cx   0         -Ixz        -Iyz         Izz    ]; % N
% % *******************************************************                      
% excitation_matrix= [Gx + mass*R*V - mass*Q*W + mass*cx*(Q^2+R^2) - mass*cy*P*Q       - mass*cz*P*R ; 
%                     Gy - mass*R*U + mass*P*W - mass*cx*P*Q       + mass*cy*(P^2+R^2) - mass*cz*Q*R ;
%                     Gz + mass*Q*U - mass*P*V - mass*cx*P*R       - mass*cy*Q*R       + mass*cz*(P^2+Q^2) ;
%                     -cz*Gy + cy*Gz - Q*R*(Izz-Iyy) - P*R*Ixy + P*Q*Ixz - (R^2-Q^2)*Iyz                     - (P*V-Q*U)*mass*cy + (R*U-P*W)*mass*cz;
%                     -cx*Gz + cz*Gx - P*R*(Ixx-Izz) + Q*R*Ixy - P*Q*Iyz - (P^2-R^2)*Ixz + (P*V-Q*U)*mass*cx                     - (Q*W-R*V)*mass*cy;
%                     -cy*Gx + cx*Gy - P*Q*(Iyy-Ixx) - Q*R*Ixz + P*R*Iyz - (Q^2-P^2)*Ixy - (R*U-P*W)*mass*cx + (Q*W-R*V)*mass*cy                   ];
                                                                    
% *******************************************************

 % Applies "cost" for moving forces applied on CG to BAC by generating the
 % associated moment.Z
Mc = [1,	0,      0,      0,  0,  0;
      0,	1,      0,      0,  0,  0;
      0,	0,      1,      0,  0,  0;
      0,	cz,     -cy,    1,  0,  0;
      -cz,	0,      cx,     0,  1,  0;
      cy,	-cx,	0,      0,  0,  1];

% Actual Eq of motion (Not needed for NDI)
% TODO 
% [Ud, Vd, Wd, Pd, Qd, Rd] = mass_matrix\(excitation_matrix + Mc * [Tbody_ext; Mbody_ext])
% vpa(eval(mass_matrix\(excitation_matrix + Mc * [Tbody_ext; Mbody_ext])), 5);
  
%% NDI Components from Eqs of motion
% TODO Mc probably is wrong and needs to be removed.
fx = mass_matrix\(excitation_matrix + Mc * hx_u0);
J_fx = jacobian(fx, [U,V,W,P,Q,R]);

% g(x) = Bv*B
Bv =  mass_matrix\Mc;
B = J_gx0;
gx_hat = Bv*B;

%% Particularise for each scenario:
% Default values
% Mass properties, inertia moments
%     m=3.51; % Total Mass   % To be changed/measured/tuned
%     m_0=  2.61; % Mass of vehicle without motors
%     m_M = 0.300; % To be changed/measured/tuned
%     CG_0= [0,0,0.02]'; % CG positions about BAC of vehicle without motors  % To be changed/measured/tuned
%     M_eq=0.001; % Equivalent mass of the proppeller ~1/5*mass_propeller  % To be changed/measured/tuned
%     Ix=0.103; % To be changed/measured/tuned
%     Iy=0.147; % To be changed/measured/tuned
%     Iz=0.237;   % To be changed/measured/tuned
%     Ixz = -0.008; % To be changed/measured/tuned
%     I_BAC_0= [ Ix,0,Ixz;0,Iy,0;Ixz,0,I     z];
%     clear Ix Iy Iz Ixz;
% Calculated /simulink_functions/mass_properties with parameters
% commented above
I_BAC_init =...
   [ 0.1602  0      -0.0080 ;
     0       0.2042  0      ;
    -0.0080  0       0.3441];
CG_init = [0         0   -0.0015];
mass = 3.51;
I_CG_init = I_BAC_init - mass * (CG_init * CG_init' * eye(3) - CG_init' * CG_init);
% Kt = 19.5;
% Kq = 0.26;
%% 9DOF with massic update
% gx_hat_9DOF = eval(gx_hat);
%% 9DOF no masic update
Ixx = I_CG_init(1,1);
Iyy = I_CG_init(2,2);
Izz = I_CG_init(3,3);
Ixy = I_CG_init(1,2);
Ixz = I_CG_init(1,3);
Iyz = I_CG_init(2,3);
cx = CG_init(1);
cy = CG_init(2);
cz = CG_init(3);
% gx_hat_9DOF_NMU = vpa(eval(gx_hat),3);
% fx_hat_9DOF_NMU = vpa(eval(fx), 3);

% t=cputime
% eval(gx_hat_9DOF_NMU)
% cputime-t
%% 4DOF with massic update
%   TODO
%% 4DOF no massic update
gamma1 = 0;
gamma1_0 = 0;
gamma2 = 0;
gamma2_0 = 0;
gamma3 = 0;
gamma3_0 = 0;
eta2 = 0;
eta2_0 = 0;
eta3 = 0;
eta3_0 = 0;
Ixx = I_CG_init(1,1);
Iyy = I_CG_init(2,2);
Izz = I_CG_init(3,3);
Ixy = I_CG_init(1,2);
Ixz = I_CG_init(1,3);
Iyz = I_CG_init(2,3);
cx = CG_init(1);
cy = CG_init(2);
cz = CG_init(3);
gx_hat_4DOF_nomass = vpa(eval(gx_hat), 5);
fx_hat_4DOF_nomass = vpa(eval(fx), 5);% %% Attainable sets

%% Trim Point
% Trim_4DOF = [  0.59, -2.298*pi/180,        0,   0.5889,             0,      0,     0.5896,      0,     0];
% Trim_9DOF = [0.6065,-0.7332*pi/180, -0.06865,   0.6061,-0.7466*pi/180,  0.427,     0.6061, 0.6022,0.4216];
% 
% % Position limits = Lineal
% % Plim_9DOF = [0,-deg2rad(165),-deg2rad(90), 0,-deg2rad(165),-deg2rad(15), 0,-deg2rad(165),-deg2rad(90);...
% %              1, deg2rad(165), deg2rad(15), 1, deg2rad(165), deg2rad(90), 1, deg2rad(165), deg2rad(15)]';
% % Plim_4DOF = [0,-deg2rad(165),           0, 0,            0,           0, 0,            0,           0;...
% %              1, deg2rad(160),           0, 1,            0,           0, 1,            0,           0]';
% Plim_9DOF = [0,-deg2rad(10),-deg2rad(10), 0,-deg2rad(10),-deg2rad(10), 0,-deg2rad(10),-deg2rad(10);...
%              0.1, deg2rad(10), deg2rad(10), 0.1, deg2rad(10), deg2rad(10), 0.1, deg2rad(10), deg2rad(10)]';
% Plim_4DOF = [0,-deg2rad(10),           0, 0,            0,           0, 0,            0,           0;...
%              0.1, deg2rad(10),           0, 0.1,            0,           0, 0.1,            0,           0]';
% 
%          
% % Linearised B matrices
% B_9DOF = double(vpa(eval(...
%     subs(gx_hat, [tau1_0, eta1_0, gamma1_0, tau2_0, eta2_0, gamma2_0, tau3_0, eta3_0, gamma3_0], Trim_9DOF))...
%                     , 5));
%                 
% B_4DOF = double(vpa(eval(...
%     subs(gx_hat, [tau1_0, eta1_0, gamma1_0, tau2_0, eta2_0, gamma2_0, tau3_0, eta3_0, gamma3_0], Trim_4DOF))...
%                     , 5));
% 
% % Call  vview function
% B_9DOF_acc = double(B_9DOF([1,2,3],:));
% B_4DOF_acc = double(B_4DOF([1,2,3],:));
% att_9DOF_Forces = vview(B_9DOF_acc,Plim_9DOF);
% att_4DOF_Forces = vview(B_4DOF_acc,Plim_4DOF);
% 
% B_9DOF_rate = double(B_9DOF([4,5,6],:));
% B_4DOF_rate = double(B_4DOF([4,5,6],:));
% att_9DOF_Mom = vview(B_9DOF_rate,Plim_9DOF);
% att_4DOF_Mom = vview(B_4DOF_rate,Plim_4DOF);
% % att_9DOF = vview(B_9DOF,Plim_9DOF,pinv(B_9DOF));
% % att_4DOF = vview(B_4DOF,Plim_4DOF,pinv(B_4DOF));


% Select components for 4DOF - WPQR
%   Input - tau1, gamma1, tau2, tau3
%   Output- accZ, p_dot, q_dot, r_dot
gx_hat_4DOF_nomass = vpa(eval(gx_hat_4DOF_nomass([3,4,5,6],[1,2,4,7])),4);
fx_hat_4DOF_nomass = vpa(eval(fx_hat_4DOF_nomass([3,4,5,6])), 4);

%% Controlability analysis for 4DOF around hovering point
% U = 0;
% V = 0;
% W = 0;
% P = 0;
% Q = 0;
% R = 0;
% % Trim input for 4 DOF [tau1, eta1, tau2, tau3] =
% % [0.59,-2.298*pi/180,0.5889,0.5896]
% gx_4DOF = vpa(eval(gx_hat_4DOF_nomass([1,2,3,4,5,6],[1,2,4,7])),4);
% fx_4DOF = vpa(eval(J_fx), 4);
% ctrb(fx_4DOF, gx_4DOF)

%% Attainable sets
% % Trim Point
% Trim_4DOF = [  0.59, -2.298*pi/180,        0,   0.5889,             0,      0,     0.5896,      0,     0];
% Trim_9DOF = [0.6065,-0.7332*pi/180, -0.06865,   0.6061,-0.7466*pi/180,  0.427,     0.6061, 0.6022,0.4216];
% 
% % Position limits = Lineal
% % Plim_9DOF = [0,-deg2rad(165),-deg2rad(90), 0,-deg2rad(165),-deg2rad(15), 0,-deg2rad(165),-deg2rad(90);...
% %              1, deg2rad(165), deg2rad(15), 1, deg2rad(165), deg2rad(90), 1, deg2rad(165), deg2rad(15)]';
% % Plim_4DOF = [0,-deg2rad(165),           0, 0,            0,           0, 0,            0,           0;...
% %              1, deg2rad(160),           0, 1,            0,           0, 1,            0,           0]';
% Plim_9DOF = [0,-deg2rad(10),-deg2rad(10), 0,-deg2rad(10),-deg2rad(10), 0,-deg2rad(10),-deg2rad(10);...
%              0.1, deg2rad(10), deg2rad(10), 0.1, deg2rad(10), deg2rad(10), 0.1, deg2rad(10), deg2rad(10)]';
% Plim_4DOF = [0,-deg2rad(10),           0, 0,            0,           0, 0,            0,           0;...
%              0.1, deg2rad(10),           0, 0.1,            0,           0, 0.1,            0,           0]';
% 8
%          
% % Linearised B matrices
% B_9DOF = double(vpa(eval(...
%     subs(gx_hat, [tau1_0, eta1_0, gamma1_0, tau2_0, eta2_0, gamma2_0, tau3_0, eta3_0, gamma3_0], Trim_9DOF))...
%                     , 5));
%                 
% B_4DOF = double(vpa(eval(...
%     subs(gx_hat, [tau1_0, eta1_0, gamma1_0, tau2_0, eta2_0, gamma2_0, tau3_0, eta3_0, gamma3_0], Trim_4DOF))...
%                     , 5));
% 
% % Call  vview function
% B_9DOF_acc = double(B_9DOF([1,2,3],:));
% B_4DOF_acc = double(B_4DOF([1,2,3],:));
% att_9DOF_Forces = vview(B_9DOF_acc,Plim_9DOF);
% att_4DOF_Forces = vview(B_4DOF_acc,Plim_4DOF);
% 
% B_9DOF_rate = double(B_9DOF([4,5,6],:));
% B_4DOF_rate = double(B_4DOF([4,5,6],:));
% att_9DOF_Mom = vview(B_9DOF_rate,Plim_9DOF);
% att_4DOF_Mom = vview(B_4DOF_rate,Plim_4DOF);
% % att_9DOF = vview(B_9DOF,Plim_9DOF,pinv(B_9DOF));
% % att_4DOF = vview(B_4DOF,Plim_4DOF,pinv(B_4DOF));


%% Outer loop NDI - Objective relate Xe_dot and Ye_dot with \phi and \theta
% % Generate global function x_dot = f(x,u)
% fgx =  mass_matrix\excitation_matrix + gx;
% % Take part relative to translational motion
% fgx_outer = fgx(1:3,:);
% % Transform to earth axis 
% % [X_dot Y_dot, Z_dot] = f_E(x,u,phi,theta,psi)
% f_E = R_E2B.'* fgx_outer;
% 
% % Linearise using Taylor approx
% % [X_dot V_dot](phi, theta) = f_E(x_0, u_0, att_0) + jac(f_E(x,u,att)) * (att - att_0)
% Assume inner dynamics are instant seen from the outer loop
% f_E = subs(f_E, [u,v,w,p,q,r], [u_0,v_0,w_0,p_0,q_0,r_0]);
% f_E = subs(f_E,[tau1, eta1, gamma1, tau2, eta2, gamma2, tau3, eta3, gamma3], u0.');
%
% % Online linearisation
% jac_E = jac(f_E, [phi, theta, psi])
% 
