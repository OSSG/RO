-- Структура таблиц БД системы RO
-- Предназначена для и тестировалась в СУБД MySQL 5.0

-- Таблица состояний пакетов
drop table if exists package_states;
create table package_states (
    `id` integer unsigned not null auto_increment primary key, -- id состояния
    `name` varchar(127) not null default '' unique  -- название состояния
)
    default character set utf8
    collate utf8_bin;

-- 1
    insert into package_states (id, name) values (1, 'Normal');
-- 2
    insert into package_states (id, name) values (2, 'Old');
-- 3
    insert into package_states (id, name) values (3, 'Orphaned');
-- 4
    insert into package_states (id, name) values (4, 'Too new');


-- Таблица состояний узлов
drop table if exists node_states;
create table node_states (
    `id` integer unsigned not null auto_increment primary key, -- id состояния
    `name` varchar(127) not null default '' unique -- название состояния
)
    default character set utf8
    collate utf8_bin;

-- 1
    insert into node_states (id, name) values (1, 'Normal');
-- 2
    insert into node_states (id, name) values (2, 'Orphaned');
-- 3
    insert into node_states (id, name) values (3, 'Trouble');

-- Таблица пакетов
drop table if exists packages;
create table packages (
    `id` integer unsigned not null auto_increment primary key, -- id пакета
    `name` varchar(127) not null default '' unique -- имя пакета
)
    default character set utf8
    collate utf8_bin;

-- Таблица узлов		  
drop table if exists nodes;
create table nodes (
    `id` integer unsigned not null auto_increment primary key, -- id узла
    `signature` char(32) not null default '', -- уникальная подпись узла
    `name` varchar(127) not null default '', -- имя системы
    `notes` text not null default '', -- краткая поясняющая информация
    `node_type` tinyint unsigned not null default 0, -- тип системы
						     -- (0 - рабочая система,
						     -- 1 - репозиторий)
    `sync_time` timestamp default 0, -- дата последней синхронизации
    `importance` tinyint unsigned not null default 1, -- индекс важности обновления узла
						      -- чем больше, тем важнее
    `to_check`	tinyint unsigned not null default 1, -- флаг необходимости проверки состояния узла
    `state` integer unsigned not null default 1, -- текущее состояние узла

    foreign key (state) references node_states(id)
)
    default character set utf8
    collate utf8_bin;

-- Связь пакетов и узлов
drop table if exists packages_vs_nodes;
create table packages_vs_nodes (
    `package` integer unsigned not null, -- id пакета
    `node` integer unsigned not null, -- id узла
    `version` varchar(31) not null default '', -- версия пакета
    `release` varchar(31) not null default '', -- релиз пакета
    `serial` varchar(15) not null default '', -- serial пакета
    `importance` tinyint unsigned not null default 1, -- индекс важности обновления пакета
						      -- чем больше, тем важнее
    `summary` text not null default '', -- summary пакета (также имеет смысл
					-- для репозиториев)
    `state` integer unsigned not null default 1, -- текущее состоание пакета в рамках узла

    foreign key (package) references packages(id),
    foreign key (node) references nodes(id),
    foreign key (state) references package_states(id)
)
    default character set utf8
    collate utf8_bin;

-- Связь рабочих систем и репозиториев
drop table if exists nodes_vs_nodes;
create table nodes_vs_nodes (
    `system` integer unsigned not null, -- id системы
    `repository` integer unsigned not null, -- id репозитория

    foreign key (system) references nodes(id),
    foreign key (repository) references nodes(id)
)
    default character set utf8
    collate utf8_bin;
