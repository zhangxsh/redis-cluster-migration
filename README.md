## redis集群间数据迁移，纯bash实现方案，简单轻量，复用度高

### 1、自动识别类型，不用写策略模式了
### 2、scan扫描，规避集群block风险
### 3、自动forward到正确的分片
### 4、自定义key，支持部分搬迁也支持整体搬迁
