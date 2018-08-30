%% Cost-balancing for LASA dataset
% This file trains GMM and GMM-delta on lasa dataset
% computes the best combination of shape and position objectives
% using optimzization


clc, clear, close all

%--------------------------------
% DESIGN PARAMETERS
%--------------------------------
doDownSampling = 0; % 1 or 0
doTimeAlignment = 1; % 1 or 0
doSmoothing = 1; % 1 or 0
fixedWeight = 1; %1e9 weight should not be used because the constraint is included in the optimization;
doConstraintIntialPoint = 1; % currently only the value 1 is supported
doConstraintEndPoint = 1; % currently only the value 1 is supported
viaPoints = []; % a nbDim x (numConstraintPoints-2) matrix in which each column represents a via point (EXCLUDING start and end point)
viaPointsTime = []; % a 1 x (numConstraintPoints-2) matrix in which each element represents the time at which the corresponding element of viaPoints has to be enforced
nbStatesPos = 5; % number of Gaussian Components (for position)
nbStatesGrad = 5; % number of Gaussian Components (for gradient)
nbStatesDelta = 5; % number of Gaussian Components (for laplacian)
folderName = 'LASA_dataset'; % folder name containing demos
demoFileIndex = 2; % skill number (index of the file in an alphabetically arranged list of all files in folderName)
ext = 'mat'; % extension of the demos

%--------------------------------
% INITIALIZATION
%--------------------------------
% add paths
addpath(genpath('LASA_dataset'));
addpath(genpath('RAIL_dataset'));
addpath(genpath('synthetic_dataset'));
addpath(genpath('encoder'));
addpath(genpath('meta_optimization'));
addpath(genpath('interactive_demonstration_recorder'));
% setup CVX toolbox
% run('C:\Users\Reza\Documents\MATLAB\cvx\cvx_setup.m')

% get all skills from the dataset folder
[skills,nskills] = getAllMatFiles(folderName, ext); % skills{1}

%--------------------------------
% SKILL LOOP (for more than 1 dataset)
%--------------------------------
load(skills{demoFileIndex});% loads a dataset including a demo cell and an average dt each demo includes pos, t, vel, acc, dt
nbDemos = size(demos,2);            % number of demos
nbNodes = size(demos{1}.pos,2);     % number of points in each demonstrations
nbDims   = size(demos{1}.pos,1);    % number of dimension (2D / 3D)

if strcmp(folderName, 'LASA_dataset')
    for i = 1:size(demos,2)
        demos{1,i}.time = demos{1,i}.t;
    end
end
%--------------------------------
% Time align the demonstrations
%--------------------------------

if doTimeAlignment
    demos = alignDataset(demos,1);
end

%--------------------------------
% DownSample
%--------------------------------
if doDownSampling
    Demos = cell(1,nbDemos);
    stp = floor(nbNodes / floor(nbNodes * 0.10));
    for ii = 1:nbDemos
        Demos{ii} = demos{ii}.pos(:,1:stp:end);
    end
    nbNodes = size(Demos{1},2);
    
else
    for ii=1:nbDemos
        Demos{ii} = demos{ii}.pos;
    end
end

clear demos dt ext foldername stp ii doDownSampling

%--------------------------------
% Smooth the demonstrations
%--------------------------------
if doSmoothing
    for ii=1:nbDemos
        for j = 1:size(Demos{ii},1)
            Demos{ii}(j,:) = smooth(Demos{ii}(j,:));
        end
    end
end

%--------------------------------
% GMM/GMR - in position space for different nbstates for comparisons
%--------------------------------
Gmms = cell(1,4);                       % to save GMM/GMR results
D1 = zeros(nbDims+1, nbDemos*nbNodes);  % restructuring the data
t = 1:nbNodes;                          % index
D1(1,:) = repmat(t, 1, nbDemos);
for ii=1:nbDemos
    D1(2:nbDims+1, (ii-1)*nbNodes+1:ii*nbNodes) = Demos{ii};
end

for ns = 4:7
    M = encodeGMM(D1, nbNodes, ns);
    [repro1, expSigma1] = reproGMM(M);
    M.repro = repro1;
    M.expSigma = expSigma1;
    Gmms{1,ns-3} = M;
end
clear D1 t ns M repro1 expSigma1

%--------------------------------
% GMM/GMR - in Laplace space
%--------------------------------
[Mu_d, R_Sigma_d, L] = trainGMML(Demos, nbDims, nbDemos, nbNodes, nbStatesDelta);

%--------------------------------
% GMM/GMR - in Gradient space
%--------------------------------
[Mu_g, R_Sigma_g, G] = trainGMMG(Demos, nbDims, nbDemos, nbNodes, nbStatesGrad);

%--------------------------------
% GMM/GMR - in position space
%--------------------------------
[Mu_x, R_Sigma_x] = trainGMM(Demos, nbDims, nbDemos, nbNodes, nbStatesPos);
% figure;hold on;
% title('GMM');
% for ii=1:nbDemos
%     plot(Demos{ii}(1,:),Demos{ii}(2,:),'color',[0.5 0.5 0.5]);
% end
% plot(Mu_x(1,:),Mu_x(2,:),'r','linewidth',2)
% bound_x = abs(max(Mu_x(1,:)) - min(Mu_x(1,:)))*0.1;
% bound_y = abs(max(Mu_x(2,:)) - min(Mu_x(2,:)))*0.1;
% axis([min(Mu_x(1,:))-bound_x max(Mu_x(1,:))+bound_x min(Mu_x(2,:))-bound_y max(Mu_x(2,:))+bound_y]);
% xticklabels([]);
% yticklabels([]);
% box on; grid on;
% ylabel('x_2','fontname','Times','fontsize',14);
% xlabel('x_1','fontname','Times','fontsize',14);

% clear bound_x bound_y ii

%--------------------------------
% Scaling the error terms
%--------------------------------
for i = 1:nbDemos
% error_d(i) = ((R_Sigma_d * reshape((L*[Demos{1,i}(1,:)' Demos{1,i}(2,:)' Demos{1,i}(3,:)'] - Mu_d.').', numel(Mu_d),1)).' * (R_Sigma_d * reshape((L*[Demos{1,i}(1,:)' Demos{1,i}(2,:)' Demos{1,i}(3,:)'] - Mu_d.').', numel(Mu_d),1)));
error_d(i) = ((R_Sigma_d * reshape((L*Demos{1,i}.' - Mu_d.').', numel(Mu_d),1)).' * (R_Sigma_d * reshape((L*Demos{1,i}.' - Mu_d.').', numel(Mu_d),1)));
end
meanError_d = mean(error_d);

for i = 1:nbDemos
error_g(i) = (R_Sigma_g * reshape((G*Demos{1,i}.' - Mu_g.').', numel(Mu_g),1)).' * (R_Sigma_g * reshape((G*Demos{1,i}.' - Mu_g.').', numel(Mu_g),1));
end
meanError_g = mean(error_g);

for i = 1:nbDemos
error_x(i) = (R_Sigma_x * reshape((Demos{1,i}.' - Mu_x.').', numel(Mu_x),1)).' * (R_Sigma_x * reshape((Demos{1,i}.' - Mu_x.').', numel(Mu_x),1));
end
meanError_x = mean(error_x);

scalingFactors = [meanError_d meanError_g meanError_x]./sum([meanError_d meanError_g meanError_x]);

%--------------------------------
% META-OPTIMIZATION
%--------------------------------
% initialization
M.nbDims = nbDims;
M.nbNodes = nbNodes;
M.fixedWeight = fixedWeight;
M.nbDemos = nbDemos;
M.L = L;
M.Mu_d = Mu_d;
M.R_Sigma_d = R_Sigma_d;
M.G = G;
M.Mu_g = Mu_g;
M.R_Sigma_g = R_Sigma_g;
M.Mu_x = Mu_x;
M.R_Sigma_x = R_Sigma_x;
M.Demos = Demos;
M.scalingFactors = scalingFactors;
M.doConstraintIntialPoint = doConstraintIntialPoint;
M.doConstraintEndPoint = doConstraintEndPoint;
M.viaPoints = viaPoints;
M.viaPointsTime = viaPointsTime;


metaSolver =  'matlab'; % 'pso' 'matlab' 'cmaes' 'use_existing';
nVars = 3; % number of varianbles/weights for meta optimization

switch metaSolver
    case 'cmaes'
        %% CMA-ES
        opts.LBounds = 0; opts.UBounds = 1;
        % opts.Restarts = 3;  % doubles the popsize for each restart
        doSoftConstraint = 1;
        [x, F_cmaes, E_cmaes, STOP, OUT] = cmaes('objfcn', rand(nVars,1), 1/6, opts, M, doSoftConstraint);
        plotcmaesdat
        
    case 'pso'
        %% PSO
        lb = 0*ones(1,nVars);
        ub = 1*ones(1,nVars);
        
        options = optimoptions('particleswarm','SwarmSize',2*nVars, 'Display', 'iter');
        doSoftConstraint = 1;
        
        fh = @(x)objfcn(x, M, doSoftConstraint);
        [x, fval, exitflag] = particleswarm(fh, nVars, lb, ub, options);
    case 'use_existing'
        x = [0.9 0.1 0.4]; % for G skill (5)
        
    case 'matlab'
        lb = 0*ones(1,nVars);
        ub = 1*ones(1,nVars);
        doSoftConstraint = 0; % no need for soft constraints since it is enforced as hard linear constraint
        
        options = optimoptions('fmincon', 'Algorithm','sqp','MaxIterations',1000); 
        
        fh = @(x)objfcn(x, M, doSoftConstraint);
        [x, fval, exitflag] = fmincon(fh, rand(nVars,1), [], [], ones(1,nVars), 1, lb, ub, [], options);
end

% output of this section is the weight between the position and shape costs

%% check the result of the meta-optimzation
w = x;     % weight

numViaPoints = length(viaPointsTime);
numConstraintPoints = numViaPoints + doConstraintIntialPoint + doConstraintEndPoint;

P_ = zeros((numConstraintPoints), nbNodes);

P_index = 1;
if(doConstraintIntialPoint)
    P_(P_index,1) = fixedWeight; % initial point
    P_index = P_index + 1;
end

if(doConstraintEndPoint)
    P_(P_index,end) = fixedWeight; % end point
    P_index = P_index + 1;
end

for i = 1:numViaPoints
    P_(P_index,viaPointsTime(i)) = fixedWeight;
    
    P_index = P_index + 1;
end

figure;
whichDemos = [1 2 3];
Sols = cell(1,length(whichDemos));
for ni = 1:length(whichDemos)
    % define the constraint
    posConstraints = [(Demos{whichDemos(ni)}(:,1)+0*rand(nbDims,1)).' ; (Demos{whichDemos(ni)}(:,end)+0*rand(nbDims,1)).'; viaPoints.']*fixedWeight;
    
    % CVX
    if nbDims == 2
        cvx_begin
        variable sol_x(nbNodes);
        variable sol_y(nbNodes);
        minimize(w(1) .*  ((R_Sigma_d * reshape((L*[sol_x sol_y] - Mu_d.').', numel(Mu_d),1)).' * (R_Sigma_d * reshape((L*[sol_x sol_y] - Mu_d.').', numel(Mu_d),1)))./scalingFactors(1) + ...
            w(2) .* ((R_Sigma_g * reshape((G*[sol_x sol_y] - Mu_g.').', numel(Mu_g),1)).' * (R_Sigma_g * reshape((G*[sol_x sol_y] - Mu_g.').', numel(Mu_g),1)))./scalingFactors(2) + ...
            w(3) .* ((R_Sigma_x * reshape(([sol_x sol_y] - Mu_x.').', numel(Mu_x),1)).' * (R_Sigma_x * reshape(([sol_x, sol_y] - Mu_x.').', numel(Mu_x),1)))./scalingFactors(3))
        % minimize(f([sol_x, sol_y]));
        subject to
        P_*[sol_x, sol_y] == posConstraints;
        cvx_end
        sol = [sol_x, sol_y];
        Sols{1,ni} = sol;
        
        % plot
        subplot(1,length(whichDemos),ni);hold on
        title('GMM- \delta');
        for ii=1:nbDemos
            plot(Demos{ii}(1,:),Demos{ii}(2,:),'color',[0.5 0.5 0.5]);
        end
        plot(sol(:,1),sol(:,2),'linewidth',2)
        plot(Mu_x(1,:),Mu_x(2,:),'--r','linewidth',2)
        bound_x = abs(max(sol_x) - min(sol_x))*0.1;
        bound_y = abs(max(sol_y) - min(sol_y))*0.1;
        axis([min(sol(:,1))-bound_x max(sol(:,1))+bound_x min(sol(:,2))-bound_y max(sol(:,2))+bound_y]);
        xticklabels([]);
        yticklabels([]);
        box on; grid on;
        ylabel('x_2','fontname','Times','fontsize',14);
        xlabel('x_1','fontname','Times','fontsize',14);
    else
        if nbDims == 3
            cvx_begin
            variable sol_x(nbNodes);
            variable sol_y(nbNodes);
            variable sol_z(nbNodes);
            minimize(w(1) .*  ((R_Sigma_d * reshape((L*[sol_x sol_y sol_z] - Mu_d.').', numel(Mu_d),1)).' * (R_Sigma_d * reshape((L*[sol_x sol_y sol_z] - Mu_d.').', numel(Mu_d),1)))./scalingFactors(1) + ...
                w(2) .* ((R_Sigma_g * reshape((G*[sol_x sol_y sol_z] - Mu_g.').', numel(Mu_g),1)).' * (R_Sigma_g * reshape((G*[sol_x sol_y sol_z] - Mu_g.').', numel(Mu_g),1)))./scalingFactors(2) + ...
                w(3) .* ((R_Sigma_x * reshape(([sol_x sol_y sol_z] - Mu_x.').', numel(Mu_x),1)).' * (R_Sigma_x * reshape(([sol_x, sol_y sol_z] - Mu_x.').', numel(Mu_x),1)))./scalingFactors(3))
            % minimize(f([sol_x, sol_y sol_z]));
            subject to
            P_*[sol_x, sol_y sol_z] == posConstraints;
            cvx_end
            sol = [sol_x, sol_y sol_z];

            % plot
            subplot(1,length(whichDemos),ni);hold on
            title('GMM- \delta');
            for ii=1:nbDemos
                plot3(Demos{ii}(1,:),Demos{ii}(2,:),Demos{ii}(3,:),'color',[0.5 0.5 0.5]);
            end
            plot3(sol(:,1),sol(:,2),sol(:,3),'linewidth',2)
            plot3(Mu_x(1,:),Mu_x(2,:),Mu_x(3,:),'--r','linewidth',2)
            axis('auto');
            xticklabels([]);
            yticklabels([]);
            zticklabels([]);
            box on; grid on;
            zlabel('x_3','fontname','Times','fontsize',14);
            ylabel('x_2','fontname','Times','fontsize',14);
            xlabel('x_1','fontname','Times','fontsize',14);
        else
            error("The current version of the software can only handle 2 and 3 dimensional spaces!")
        end
    end
end

for ii=1:length(whichDemos); subplot(1,length(whichDemos),ii);axis auto;end
return
% save the important variables for plotting later
filenamesaved = ['skill_' num2str(kk) '_trained.mat'];
save(filenamesaved,'Demos','Gmms','Sols','w');