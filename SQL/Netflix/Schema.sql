-- SCHEMAS of Netflix

DROP TABLE IF EXISTS netflix_;
CREATE TABLE netflix_
(
    show_id       VARCHAR(5) PRIMARY KEY,
    content_type  VARCHAR(10),
    title         VARCHAR(250),
    director      VARCHAR(550),
	casts	      VARCHAR(1050),
    country       VARCHAR(550),
    date_added    VARCHAR(55), 
    release_year  INT,
    rating        VARCHAR(15),
    duration      VARCHAR(55), 
    listed_in     VARCHAR(250),
    description   VARCHAR(1050)
);
