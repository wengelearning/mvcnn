function shape_train(imdb, opts, varargin)
% SHAPE_TRAIN Train a CNN model on a dataset supplied by imdb

opts.lite = false ;
opts.numFetchThreads = 0 ;
opts.train.batchSize = 256 ;
opts.train.numEpochs = 65 ;
opts.train.continue = true ;
opts.train.useGpu = false ;
opts.train.prefetch = false ;
opts.train.learningRate = [0.001*ones(1, 25) 0.0001*ones(1, 25) 0.00001*ones(1,15)] ;
opts.train.expDir = opts.expDir ;
opts = vl_argparse(opts, varargin) ;

% -------------------------------------------------------------------------
%                                                    Network initialization
% -------------------------------------------------------------------------

net = initializeNetwork(imdb, opts) ;

% Initialize average image
if isempty(net.normalization.averageImage), 
    % compute the average image
    averageImagePath = fullfile(opts.expDir, 'average.mat') ;
    if exist(averageImagePath, 'file')
      load(averageImagePath, 'averageImage') ;
    else
      train = find(imdb.images.set == 1) ;
      bs = 256 ;
      fn = getBatchWrapper(net.normalization, opts.numFetchThreads) ;
      for t=1:bs:numel(train)
        batch_time = tic ;
        batch = train(t:min(t+bs-1, numel(train))) ;
        fprintf('computing average image: processing batch starting with image %d ...', batch(1)) ;
        temp = fn(imdb, batch) ;
        im{t} = mean(temp, 4) ;
        batch_time = toc(batch_time) ;
        fprintf(' %.2f s (%.1f images/s)\n', batch_time, numel(batch)/ batch_time) ;
      end
      averageImage = mean(cat(4, im{:}),4) ;
      save(averageImagePath, 'averageImage') ;
    end

    net.normalization.averageImage = averageImage ;
    clear averageImage im temp ;
end

% -------------------------------------------------------------------------
%                                               Stochastic gradient descent
% -------------------------------------------------------------------------
fn = getBatchWrapper(net.normalization, opts.numFetchThreads) ;

[net,info] = cnn_train(net, imdb, fn, opts.train, 'conserveMemory', true) ;

% -------------------------------------------------------------------------
function fn = getBatchWrapper(opts, numThreads)
% -------------------------------------------------------------------------
fn = @(imdb,batch) getBatch(imdb,batch,opts,numThreads) ;

% -------------------------------------------------------------------------
function [im,labels] = getBatch(imdb, batch, opts, numThreads)
% -------------------------------------------------------------------------
images = strcat([imdb.imageDir '/'], imdb.images.name(batch)) ;
im = imdb_get_batch(images, opts, ...
                            'numThreads', numThreads, ...
                            'prefetch', nargout == 0, ...
                            'augmentation', 'f25') ;
labels = imdb.images.label(batch) ;

% -------------------------------------------------------------------------
function net = initializeNetwork(imdb, opts)
% -------------------------------------------------------------------------
scal = 1 ;
init_bias = 0.1;
numClass = length(imdb.classes.name);
if ~isempty(opts.model)
    net = load(fullfile('data/models', opts.model)); % Load model if specified
    fprintf('Initializing from model: %s\n', opts.model);

    % Replace the last but one layer with random weights
    net.layers{end-1} = struct('type', 'conv', ...
                           'filters', 0.01/scal * randn(1,1,4096,numClass,'single'), ...
                           'biases', zeros(1, numClass, 'single'), ...
                           'stride', 1, ...
                           'pad', 0, ...
                           'filtersLearningRate', 1, ...
                           'biasesLearningRate', 2, ...
                           'filtersWeightDecay', 1, ...
                           'biasesWeightDecay', 0);
                       
    % Last layer is softmaxloss (switch to softmax for prediction)
    net.layers{end+1} = struct('type', 'softmaxloss') ;

    % Rename classes
    net.classes.name = imdb.classes.name;
    net.classes.description = imdb.classes.name;
    return;
end

% Else initial model randomly
net.layers = {} ;

% Block 1
net.layers{end+1} = struct('type', 'conv', ...
                           'filters', 0.01/scal * randn(11, 11, 3, 96, 'single'), ...
                           'biases', zeros(1, 96, 'single'), ...
                           'stride', 4, ...
                           'pad', 0, ...
                           'filtersLearningRate', 1, ...
                           'biasesLearningRate', 2, ...
                           'filtersWeightDecay', 1, ...
                           'biasesWeightDecay', 0) ;
net.layers{end+1} = struct('type', 'relu') ;
net.layers{end+1} = struct('type', 'pool', ...
                           'method', 'max', ...
                           'pool', [3 3], ...
                           'stride', 2, ...
                           'pad', 0) ;
net.layers{end+1} = struct('type', 'normalize', ...
                           'param', [5 1 0.0001/5 0.75]) ;

% Block 2
net.layers{end+1} = struct('type', 'conv', ...
                           'filters', 0.01/scal * randn(5, 5, 48, 256, 'single'), ...
                           'biases', init_bias*ones(1, 256, 'single'), ...
                           'stride', 1, ...
                           'pad', 2, ...
                           'filtersLearningRate', 1, ...
                           'biasesLearningRate', 2, ...
                           'filtersWeightDecay', 1, ...
                           'biasesWeightDecay', 0) ;
net.layers{end+1} = struct('type', 'relu') ;
net.layers{end+1} = struct('type', 'pool', ...
                           'method', 'max', ...
                           'pool', [3 3], ...
                           'stride', 2, ...
                           'pad', 0) ;
net.layers{end+1} = struct('type', 'normalize', ...
                           'param', [5 1 0.0001/5 0.75]) ;

% Block 3
net.layers{end+1} = struct('type', 'conv', ...
                           'filters', 0.01/scal * randn(3,3,256,384,'single'), ...
                           'biases', init_bias*ones(1,384,'single'), ...
                           'stride', 1, ...
                           'pad', 1, ...
                           'filtersLearningRate', 1, ...
                           'biasesLearningRate', 2, ...
                           'filtersWeightDecay', 1, ...
                           'biasesWeightDecay', 0) ;
net.layers{end+1} = struct('type', 'relu') ;

% Block 4
net.layers{end+1} = struct('type', 'conv', ...
                           'filters', 0.01/scal * randn(3,3,192,384,'single'), ...
                           'biases', init_bias*ones(1,384,'single'), ...
                           'stride', 1, ...
                           'pad', 1, ...
                           'filtersLearningRate', 1, ...
                           'biasesLearningRate', 2, ...
                           'filtersWeightDecay', 1, ...
                           'biasesWeightDecay', 0) ;
net.layers{end+1} = struct('type', 'relu') ;

% Block 5
net.layers{end+1} = struct('type', 'conv', ...
                           'filters', 0.01/scal * randn(3,3,192,256,'single'), ...
                           'biases', init_bias*ones(1,256,'single'), ...
                           'stride', 1, ...
                           'pad', 1, ...
                           'filtersLearningRate', 1, ...
                           'biasesLearningRate', 2, ...
                           'filtersWeightDecay', 1, ...
                           'biasesWeightDecay', 0) ;
net.layers{end+1} = struct('type', 'relu') ;
net.layers{end+1} = struct('type', 'pool', ...
                           'method', 'max', ...
                           'pool', [3 3], ...
                           'stride', 2, ...
                           'pad', 0) ;

% Block 6
net.layers{end+1} = struct('type', 'conv', ...
                           'filters', 0.01/scal * randn(6,6,256,4096,'single'),...
                           'biases', init_bias*ones(1,4096,'single'), ...
                           'stride', 1, ...
                           'pad', 0, ...
                           'filtersLearningRate', 1, ...
                           'biasesLearningRate', 2, ...
                           'filtersWeightDecay', 1, ...
                           'biasesWeightDecay', 0) ;
net.layers{end+1} = struct('type', 'relu') ;
net.layers{end+1} = struct('type', 'dropout', ...
                           'rate', 0.5) ;

% Block 7
net.layers{end+1} = struct('type', 'conv', ...
                           'filters', 0.01/scal * randn(1,1,4096,4096,'single'),...
                           'biases', init_bias*ones(1,4096,'single'), ...
                           'stride', 1, ...
                           'pad', 0, ...
                           'filtersLearningRate', 1, ...
                           'biasesLearningRate', 2, ...
                           'filtersWeightDecay', 1, ...
                           'biasesWeightDecay', 0) ;
net.layers{end+1} = struct('type', 'relu') ;
net.layers{end+1} = struct('type', 'dropout', ...
                           'rate', 0.5) ;

% Block 8
net.layers{end+1} = struct('type', 'conv', ...
                           'filters', 0.01/scal * randn(1,1,4096,numClass,'single'), ...
                           'biases', zeros(1, numClass, 'single'), ...
                           'stride', 1, ...
                           'pad', 0, ...
                           'filtersLearningRate', 1, ...
                           'biasesLearningRate', 2, ...
                           'filtersWeightDecay', 1, ...
                           'biasesWeightDecay', 0) ;

% Block 9
net.layers{end+1} = struct('type', 'softmaxloss') ;

% Other details
net.normalization.imageSize = [227, 227, 3] ;
net.normalization.interpolation = 'bicubic' ;
net.normalization.border = 256 - net.normalization.imageSize(1:2) ;
net.normalization.averageImage = [] ;
net.normalization.keepAspect = true ;

