OBJECTIVE: 

/*The mkvars macro essentially works like a transpose where if you had a dataset with 2 variables
  patid and pregdt and the dataset had 4 observations, 2 obs where patid=1 and 2 obs where patid = 2 then all the dates related
  to a patid are compuiled onto 1 line and if the last.patid statement is used it keeps the observation that has all the 
  pregdts relevant to that patid which makes comparison of dates possible. You will see this macro many times and it works
  the same way every time

  Original Data   What the macro does to the orig data  Final data when last.var is used

  patid pregdt   |   patid   pregdt_1    pregdt_2     |   patid   pregdt_1    pregdt_2
    1     2011   |     1         2011         .       |     1         2011        2012
    1     2012   |     1         2011         2012    |     2         2013        2014
    2     2013   |     2         2013         .       |        
    2     2014   |     2         2013         2014    |            
  
*/
%macro mkvars(counter);
    if counter=&counter then do; 
        anstab_pregdt_&counter=anstab_pregdt; anstab_gesage_&counter=anstab_gesage;   
    end; 
%mend mkvars;

%macro anstab(); 

/*ANSTAB_pregdt: Select the observations that have gestational ages */
data anstab_gesage;
    set permhope.anstab(where=(qnum=6 and resp1 ne '')); /*qnum=6 corresponds to the following question:
                                                           'Enter the participant's gestational age (in weeks) by best obstetric estimates.|*/
    anstab_gesage=input(resp1, best3.); 
    label anstab_gesage='Gestational Age from Anstab';
    keep patid anstab_gesage; 
run; 

/*ANSTAB_pregdt: Select the observations that have preg dates */
data anstab_pregdt;
    set permhope.anstab(where=(qnum=11 and resp1 ne '')); /*qnum=11 corresponds to the following question:
                                                           'Enter the participant's most recent delivery date.*/
    anstab_pregdt=input(resp1, anydtdte10.); 
    format anstab_pregdt date9.;
    label anstab_pregdt='Pregnancy Outcome Date from Anstab';
    keep patid anstab_pregdt; 
run; 

/*ANSTAB: Contains patid and either a gesage or pregdt for every patid in Anstab*/
data anstab; 
    merge anstab_gesage(in=ingesage) anstab_pregdt(in=inpregdt) dervhope.master(in=inmaster keep=patid stratcat2 randdt); 
    by patid;  
    if ingesage or inpregdt; 

    /*Subset for pregnant participants and for recently delivered or within 1-year postpartum participants. For the recently delivered or within 
      1-year postpartum participants, we want the "most recent" pregnancy which refers to the pregnancy with an outcome date closest to but not 
      after the randdt. 

      This block of code doesn't need to use entryvisdt/enrtystratcat2(which you will see used in QLW0360 and EVW0179) because anstab is tied to 
      enrollment(compared to the other sources that are based on visit). The example below will help to visualize this a bit better: 

      A participant enrolls as pregnant. This means in anstab, the participant will have gestational week but no pregdt (as the outcome didnt happen 
      as of randdt). The participants entry visit doesnt happen until the participant gives birth and is 3 months postpartum. Therefore, the 
      entrystratcat will be postpartum at the entryvisdt, and this participant will have data in the other forms that indicate pregdt, gestational age, 
      etc. to calculate the lmpdt. So effectively the info from anstab wont get used for this participant.

    */
    
    if stratcat2 = 2 or (stratcat2 in (3,4) and anstab_pregdt ne . and anstab_pregdt<=randdt);


    keep patid anstab_pregdt anstab_gesage; 

run; 

/*Store max number of pregnancies in a macro variable to be used later*/
proc sql noprint;
    select max(count) into :max_anstab_dts
    from (
        select patid, count(*) as count
        from anstab
        group by patid);
quit;


/*If a patid has more than 1 pregdt then further processing is needed to figure out which date to select*/
%if &max_anstab_dts > 1 %then %do; 
    
    proc sort data=anstab; 
        by patid; 
    run; 

    data anstab; 
        merge anstab(in=inanstab) dervhope.master(in=inmaster keep=patid stratcat2 randdt); 
        by patid;
        if inanstab;    

        /* Initialize new pregdt and gesage dummy variables */
        %do i = 1 %to &max_anstab_dts;
            length anstab_pregdt_&i 5 anstab_gesage_&i 3;
        %end; 

        /*Retain dummy pregdt and gesage vars to hold values of pregdts and gesage for a given patid*/
        retain anstab_pregdt_1-anstab_pregdt_%sysfunc(compress(&max_anstab_dts)) 
               anstab_gesage_1-anstab_gesage_%sysfunc(compress(&max_anstab_dts)) 
               counter; 
        
        /*Define arrays to store multiple pregdts and gesages*/ 
        array retarr_pregdts{*} anstab_pregdt_1-anstab_pregdt_%sysfunc(compress(&max_anstab_dts)); 
        array retarr_gesage{*} anstab_gesage_1-anstab_gesage_%sysfunc(compress(&max_anstab_dts));

        /*Call mkvars macro */
        %do i=1 %to &max_anstab_dts;
            %mkvars(&i); 
        %end; 

        drop i anstab_pregdt anstab_gesage; 

        /*Observation where last.patid is true is where all dummy pregdts and gesages will be found*/
        if last.patid;  
    run; 

    data anstab; 
        set anstab;
        /* Initialize the variables to assign final preg date and gesage to*/
        length anstab_pregdt 5 anstab_gesage 3; 
        anstab_pregdt = .;
        anstab_gesage = .;

        /* Define an array with the date variables */
        array pregdts{*} anstab_pregdt_1-anstab_pregdt_%sysfunc(compress(&max_anstab_dts));
        array gesages{*} anstab_gesage_1-anstab_gesage_%sysfunc(compress(&max_anstab_dts));
        
        /*
           This code identifies the pregnancy outcome date that is closest to but not after 
           the enrollment date (randdt) for participants who are recently delivered or within 
           1 year postpartum.
           
           - It initializes a variable `min_diff` to store the minimum difference between 
             pregnancy outcome dates and the enrollment date.
           
           - The code loops through an array of pregnancy dates (`pregdts`), checking each 
             non-missing date that is on or before the enrollment date (`randdt`).
           
           - For each valid date, the code calculates the absolute difference between the 
             pregnancy date and the enrollment date.
           
           - If the current difference is smaller than the previously recorded `min_diff` 
             (or if `min_diff` is missing, which happens on the first valid check), the 
             code updates `min_diff` and assigns the current pregnancy date to `anstab_pregdt`.
           
           - This ensures that `anstab_pregdt` holds the pregnancy date that is closest to 
             but not after the enrollment date.
        */

        min_diff = .;

        do i = 1 to dim(pregdts);
            if not missing(pregdts[i]) and pregdts[i] <= randdt then do; 
                diff = abs(randdt - pregdts[i]); 
                if missing(min_diff) or diff < min_diff then do; 
                    min_diff = diff;
                    anstab_pregdt = pregdts[i]; 
                end; 
            end;
        end;
 
        /* This code assigns the gestational age (`anstab_gesage`) that corresponds to the 
           pregnancy date (`anstab_pregdt`) found in the previous step.
           
           - The function `whichn` identifies the position (`x`) of `anstab_pregdt` in the 
             array of pregnancy dates (`pregdts[*]`).
           
           - If `anstab_pregdt` is not missing, the code uses the index `x` to assign the 
             corresponding gestational age from the `gesgaes` array to `anstab_gesage`. */

        x=whichn(anstab_pregdt, of pregdts[*]); 
        if anstab_pregdt ne . then anstab_gesage = gesgaes[x]; 

        keep patid anstab_pregdt anstab_gesage; 
    run; 

%end;
 
%mend anstab;  

%anstab(); 

%macro mkvars(counter);
    if counter=&counter then do; 
        pregdt0360_&counter=pregdt0360; gesage0360_&counter=gesage0360;   
    end; 
%mend mkvars;

%macro QLW0360(); 
/*Getting pregdt and gesage from QLW0360. */
data QLW0360; 
  merge dervhope.master(in=inmaster keep=patid entrystratcat2 stratcat2 randdt entryvisdt) 
        permhope.QLW0360(in=inqlw keep=patid pgoutdt1 pgdur1 pgoutdt2 pgdur2
                         where=(pgoutdt1 ne . or pgoutdt2 ne .)); 
  by patid; 
  if inqlw; 

  length pregdt0360 5 gesage0360 3;  
  
  pregdt0360 = .; /* Initialize pregdt0360 to hold the selected date*/

    /*
       This code selects the closest pregnancy outcome date (`pregdt0360`) on or before 
       the entry visit date (`entryvisdt`) from two possible dates: `pgoutdt1` and `pgoutdt2`.

       - The block runs only if `entrystratcat2` is not missing.
       
       - First, it checks if both `pgoutdt1` and `pgoutdt2` are non-missing.
         - If both dates are on or before the entry visit date, the code compares the 
           absolute differences between each date and `entryvisdt`. The date closer to 
           `entryvisdt` is assigned to `pregdt0360`.
         - If only one of the dates is on or before `entryvisdt`, that date is assigned 
           to `pregdt0360`.
       
       - If only one of `pgoutdt1` or `pgoutdt2` is non-missing and on or before 
         `entryvisdt`, that date is directly assigned to `pregdt0360`.
       
       - This logic ensures that `pregdt0360` is the pregnancy outcome date closest to 
         the entry visit date, provided it does not occur after the entry visit.
    */

  
  %if entrystratcat2 ne . %then %do; 
    if not missing(pgoutdt1) and not missing(pgoutdt2) then do;

        if pgoutdt1 <= entryvisdt and pgoutdt2 <= entryvisdt then do;
                
            if abs(entryvisdt - pgoutdt1) < abs(entryvisdt - pgoutdt2) then pregdt0360 = pgoutdt1;
            else pregdt0360 = pgoutdt2;

        end;
     
        else if pgoutdt1 <= entryvisdt then pregdt0360 = pgoutdt1;  
        else if pgoutdt2 <= entryvisdt then pregdt0360 = pgoutdt2;

    end;
    
    else if not missing(pgoutdt1) and pgoutdt1 <= entryvisdt then pregdt0360 = pgoutdt1;
    else if not missing(pgoutdt2) and pgoutdt2 <= entryvisdt then pregdt0360 = pgoutdt2;
  %end; 
  /*In the event that the entryvisit did not occur, the code below does the same as the block above except it compares the pgoutdt vars to the randdt*/
  %else %if entrystratcat2 = . %then %do;
    if not missing(pgoutdt1) and not missing(pgoutdt2) then do;

        if pgoutdt1 <= randdt and pgoutdt2 <= randdt then do;
                
            if abs(randdt - pgoutdt1) < abs(randdt - pgoutdt2) then pregdt0360 = pgoutdt1;
            else pregdt0360 = pgoutdt2;

        end;

        else if pgoutdt1 <= randdt then pregdt0360 = pgoutdt1;
   
        else if pgoutdt2 <= randdt then pregdt0360 = pgoutdt2;

    end;

    else if not missing(pgoutdt1) and pgoutdt1 <= randdt then pregdt0360 = pgoutdt1;
    else if not missing(pgoutdt2) and pgoutdt2 <= randdt then pregdt0360 = pgoutdt2;  
  %end; 
  
  /*Match the gesage with the corresponding pgoutdt*/
  if      pregdt0360=pgoutdt1 then pgdur=pgdur1; 
  else if pregdt0360=pgoutdt2 then pgdur=pgdur2; 

  /* Set gesage to larger approximate gesage(refer to CRF if needed) according to Jessica's 
     "Calculating threshold window for earliest RNA CD4" word doc found in: home/phacs/HOPE/documents/programming*/
  if      pgdur=1 then gesage0360=8; 
  else if pgdur=2 then gesage0360=13;
  else if pgdur=3 then gesage0360=26;
  else if pgdur=4 then gesage0360=36; 
  else if pgdur=5 then gesage0360=40;
  else if pgdur=6 then gesage0360=.; /*6 corresponds to 'Unknown' in the CRF*/

  if gesage0360 = . then gesage0360 = 40; /*Jessica's document says if gestational age is missing, assume 40 weeks gestation*/

  keep patid pregdt0360 gesage0360 entrystratcat2 stratcat2 randdt entryvisdt; 

  format pregdt0360 date9.;
  label pregdt0360='Pregnancy Outcome Date from QLW0360'
        gesage0360='Gestational Age from QLW0360'; 
run; 


/*Store max number of pregnancies in a macro variable to be used later*/
proc sql noprint;
    select max(count) into :max_qlw0360_dts
    from (
        select patid, count(*) as count
        from QLW0360
        group by patid
        having count(*) > 1
        );
quit;

/*If a participant had more than 2 pregancies within the last 12 months, a second sequence of this CRF was filled out which means
  there's atleast a third date of pregnancy outcome that has to be looked at so further processing is required*/
%if &max_qlw0360_dts > 1 %then %do; 
    
    proc sort data=qlw0360; 
        by patid; 
    run;

    data qlw0360; 
        set qlw0360; 
        by patid; 
        /* Create the new variables */
        %do i = 1 %to &max_qlw0360_dts;
            length pregdt0360_&i 5 gesage0360_&i 3;
        %end; 

        /*Retain dummy pregdt and gesage vars to hold values of pregdts and gesage for a given patid*/
        retain pregdt0360_1-pregdt0360_%sysfunc(compress(&max_qlw0360_dts)) 
               gesage0360_1-gesage0360_%sysfunc(compress(&max_qlw0360_dts)) 
               counter;    
        
        /*Define arrays to store multiple pregdts and gesages*/ 
        array pregdts{*} pregdt0360_1-pregdt0360_%sysfunc(compress(&max_qlw0360_dts)); 
        array gesages{*} gesage0360_1-gesage0360_%sysfunc(compress(&max_qlw0360_dts));

        /*Initialize dummy vars*/
        if first.patid then do; 
            counter=1;
            do i=1 to dim(pregdts); 
               pregdts(i)=.; 
               gesages(i)=.;
            end; 
        end; 
        else counter+1; 

        /*Call mkvars macro */
        %do i=1 %to &max_qlw0360_dts; 
            %mkvars(&i); 
        %end; 

        drop i pregdt0360 gesage0360; 

        /*Observation where last.patid is true is where all dummy pregdts and gesages will be found*/
        if last.patid;  
    run; 
    
    data qlw0360; 
        set qlw0360;
        /* Initialize the variable to assign final date and gesage to*/
        length pregdt0360 5 gesage0360 3; 
        pregdt0360 = .;
        gesage0360 = .;

        /* Define an array with the date variables */
        array pregdts[*] pregdt0360_1-pregdt0360_%sysfunc(compress(&max_qlw0360_dts));
        array gesages{*} gesage0360_1-gesage0360_%sysfunc(compress(&max_qlw0360_dts));
        
        /* Initialize the minimum difference */
        min_diff = .;

        /*
           This code identifies the closest pregnancy date (`pregdt0360`) on or before 
           the entry visit date (`entryvisdt`) from an array of pregnancy dates (`pregdts`).

           - The block runs only if `entrystratcat2` is not missing.
           
           - The code loops through each element in the array `pregdts`.
             - For each date, it checks if the date is non-missing and occurs on or before 
               the entry visit date (`entryvisdt`).
             - It calculates the absolute difference (`diff`) between the current date 
               and `entryvisdt`.
             - If this difference is smaller than the current minimum difference (`min_diff`) 
               (or if `min_diff` is missing, indicating the first valid date), the code 
               updates `min_diff` and assigns the current date to `pregdt0360`.

           - This process ensures that `pregdt0360` holds the date from the array that is 
             closest to but not after the entry visit date.
        */


        %if entrystratcat2 ne . %then %do; 
            do i = 1 to dim(pregdts);
                if not missing(pregdts[i]) and pregdts[i] <= entryvisdt then do; 
                    diff = abs(entryvisdt - pregdts[i]); 
                    if missing(min_diff) or diff < min_diff then do; 
                        min_diff = diff;
                        pregdt0360 = pregdts[i]; 
                    end; 
                end;
            end;
        %end; 
        /*If entryvisit did not happen, then the following block of code does the same as above except pregdts are compared to randdt instead of entryvisitdt*/
        %else %if entrystratcat2 = . %then %do; 
            do i = 1 to dim(pregdts);
                if not missing(pregdts[i]) and pregdts[i] <= randdt then do; 
                    diff = abs(randdt - pregdts[i]); 
                    if missing(min_diff) or diff < min_diff then do; 
                        /*If so, it updates min_diff and sets pregdt0360 to the current date*/
                        min_diff = diff;
                        pregdt0360 = pregdts[i]; 
                    end; 
                end;
            end;
        %end; 
        
        /* This code assigns the gestational age (`gesage0360`) corresponding to the 
           closest pregnancy date (`pregdt0360`) from the array of pregnancy dates (`pregdts`).

           - The `whichn` function finds the position (`x`) of `pregdt0360` within the array 
             `pregdts[*]`.
           
           - If `pregdt0360` is not missing, the code uses the index `x` to assign the 
             corresponding gestational age from the `gesages` array to `gesage0360`. */

        x=whichn(pregdt0360, of pregdts[*]); 

        if pregdt0360 ne . then gesage0360 = gesages[x]; 

        /*Jessica's document says if gestational age is missing, assume 40 weeks gestation*/
        if gesage0360 = . then gesage0360 = 40; 

        keep patid pregdt0360 gesage0360; 
    run;     

%end;  

%mend QLW0360; 

%qlw0360();

%macro mkvars(counter);
    if counter=&counter then do; 
        pregdt0379_&counter=pregdt0379; gesage0379_&counter=gesage0379;   
    end; 
%mend mkvars;

%macro evw0379(); 

proc sql noprint;
    /*Store all pregdt1, pregdt2, etc. vars in a macro variable called pregdt_vars*/    
    select name 
    into :pregdt_vars separated by ' '
    from dictionary.columns
    where libname='PERMHOPE' 
      and memname=upcase("EVW0379") 
      and upcase(name) like upcase("pregdt%")
      and upcase(name) ne upcase("pregdt");

    /* Count the number of pregdt variables */
    select count(name) 
    into :num_pregdt_vars
    from dictionary.columns
    where libname='PERMHOPE' 
      and memname=upcase("EVW0379") 
      and upcase(name) like upcase("pregdt%")
      and upcase(name) ne upcase("pregdt");  

    /*Store all f1gesage, f2gesage, etc. vars in a macro variable called gesage_vars*/  
    select name 
    into :gesage_vars separated by ' '
    from dictionary.columns
    where libname='PERMHOPE' 
      and memname=upcase("EVW0379") 
      and upcase(name) like '%GESAGE%';

quit; 

/*Getting pregdt and gesage from evw0379. */
data evw0379;
  merge dervhope.master  (in=inmaster keep=patid entrystratcat2 stratcat2 randdt entryvisdt) 
        permhope.evw0379 (in=inevw keep=patid entryvis &pregdt_vars &gesage_vars); 
   by patid;

   if inevw;

   /* Filter for obs where atleast one pregdt is not missing */
   if cmiss(of &pregdt_vars.) < &num_pregdt_vars.;

   /*This CRF is also completed at follow-up visits but for date calculation purposes you only need the entry visit form(s)*/
   if entryvis = 1; 

   length pregdt0379 5 gesage0379 3; 

   /*Define arrays to store date of pregnancy outcome for each fetus and corresponding gesages*/
   array pregdts {*} &pregdt_vars;
   array gesages {*} &gesage_vars;

   /*The `coalesce` function selects the first non-missing value from the list 
     of pregnancy dates (`pregdt1` to `pregdt<num_pregdt_vars>`), dynamically 
     determined by the macro variable `&num_pregdt_vars`; these are potentially 
     twins/triplets, etc. so since the dates will be nearly identical, it
     doesn't matter which one we use.
       
     The `whichn` function finds the position (`x`) of `pregdt0379` within the 
     `pregdts` array.
       
     If `pregdt0379` is not missing, the code assigns the corresponding 
     gestational age from the `gesages` array to `gesage0379` using the index `x`.*/

   pregdt0379 = coalesce(of pregdt1-pregdt%sysfunc(compress(&num_pregdt_vars)));
   x=whichn(pregdt0379, of pregdts[*]); 
   if pregdt0379 ne . then gesage0379=gesages[x]; 

   /*Subset the data based on if pregdt0379 is <= entryvisitdt or <= randdt if entryvisitdt is missing*/
   %if entrystratcat2 ne . %then %do; 
      if pregdt0379<=entryvisdt; 
   %end; 
   %else %if entrystratcat2 = . %then %do; 
      if pregdt0379<=randdt;
   %end; 

   keep patid stratcat2 randdt entryvisdt pregdt0379 gesage0379;

   format pregdt0379 date9.;
run; 

/*Store max number of pregnancies in a macro variable to be used later*/
proc sql;
    select max(count) into :max_evw0379_dts
    from (
        select patid, count(*) as count
        from evw0379
        group by patid
        );
quit;

/*If more than 1 pregnancy for a patid, then there's more processing required to evaluate all pregnancy outcome dates for a given patid*/
%if &max_evw0379_dts > 1 %then %do; 
    
    proc sort data=evw0379; 
        by patid; 
    run; 

    data evw0379; 
        set evw0379; 
        by patid; 
        /* Create the new variables */
        %do i = 1 %to &max_evw0379_dts;
            length pregdt0379_&i 5 gesage0379_&i 3;
        %end; 

        /*Retain dummy pregdt and gesage vars to hold values of pregdts and gesage for a given patid*/
        retain pregdt0379_1-pregdt0379_%sysfunc(compress(&max_evw0379_dts)) 
               gesage0379_1-gesage0379_%sysfunc(compress(&max_evw0379_dts)) 
               counter;    
        
        /*Define arrays to store multiple pregdts and gesages*/ 
        array pregdts{*} pregdt0379_1-pregdt0379_%sysfunc(compress(&max_evw0379_dts)); 
        array gesages{*} gesage0379_1-gesage0379_%sysfunc(compress(&max_evw0379_dts));

        if first.patid then do; 
            counter=1;
            do i=1 to dim(pregdts); 
               pregdts(i)=.; 
               gesages(i)=.;
            end; 
        end; 
        else counter+1;  

        /*Call mkvars macro */
        %do i=1 %to &max_evw0379_dts; 
            %mkvars(&i); 
        %end; 

        drop i pregdt0379 gesage0379; 

        /*Observation where last.patid is true is where all dummy pregdts and gesages will be found*/
        if last.patid; 
    run; 

    data evw0379; 
        set evw0379;
        /* Initialize the variable to assign final date and gesage to*/
        length pregdt0379 5 gesage0379 3; 
        pregdt0379 = .;
        gesage0379 = .;
        /* Define an array with the date variables */
        array pregdts[*] pregdt0379_1-pregdt0379_%sysfunc(compress(&max_evw0379_dts));
        array gesages{*} gesage0379_1-gesage0379_%sysfunc(compress(&max_evw0379_dts));
        
        /* Initialize the minimum difference */
        min_diff = .;
        
        /*This code block checks if `entrystratcat2` is not missing and, if so, 
           iterates through the array of pregnancy dates (`pregdts`) to find the 
           closest date that is on or before `entryvisdt`.

           - For each date, it verifies that the date is non-missing and less than 
             or equal to `entryvisdt`, calculating the absolute difference between 
             `entryvisdt` and the current date.

           - It checks if this difference is less than the current minimum difference 
             (`min_diff`) or if `min_diff` is missing, indicating the first valid date.

           - If the current date is closer, it updates `min_diff` and assigns the 
             current pregnancy date to `pregdt0379`.*/


        %if entrystratcat2 ne . %then %do; 
            do i = 1 to dim(pregdts);
                if not missing(pregdts[i]) and pregdts[i] <= entryvisdt then do; 
                    diff = abs(entryvisdt - pregdts[i]); 
                    if missing(min_diff) or diff < min_diff then do; 
                        /*If so, it updates min_diff and sets pregdt0379 to the current date*/
                        min_diff = diff;
                        pregdt0379 = pregdts[i]; 
                    end; 
                end;
            end;
        %end;
        /*If entryvisit did not happen, then the following block of code does the same thing as the above except it compares pregdts to randdt instead of entryvisitdt*/
        %else %if entrystratcat2 = . %then %do; 
            do i = 1 to dim(pregdts);
                if not missing(pregdts[i]) and pregdts[i] <= randdt then do; 
                    diff = abs(randdt - pregdts[i]); 
                    if missing(min_diff) or diff < min_diff then do; 
                        min_diff = diff;
                        pregdt0379 = pregdts[i]; 
                    end; 
                end;
            end;
        %end; 
        
        /* This code segment determines the index of the closest valid pregnancy date 
           (`pregdt0379`) within the array of pregnancy dates (`pregdts`).

           - The `whichn` function is used to find the position (`x`) of `pregdt0379` 
             in the `pregdts` array.

           - If `pregdt0379` is not missing, the code assigns the corresponding 
             gestational age from the `gesages` array to `gesage0379` using the index `x`.*/

        x=whichn(pregdt0379, of pregdts[*]); 
        if pregdt0379 ne . then gesage0379 = gesages[x]; 

        keep patid pregdt0379 gesage0379; 
    run;     
%end; 

%mend evw0379; 

%evw0379; 

/*Keep obs where participant is currently pregnant and lmptdt is not missing*/
proc sort data=permhope.evw0380 out=evw0380_sort(keep=patid lmpdt pregnow where=(pregnow=1 and lmpdt ne .));
  by patid; 
run; 

%macro evw0380(); 
/*For currently pregnant patids, keeping pregnancy with lmpdt before entryvisitdt; or before randdt if entryvisit did not happen yet */
data evw0380(drop=entrystratcat2 stratcat2 entryvisdt randdt pregnow); 
    merge evw0380_sort dervhope.master(keep=patid entrystratcat2 stratcat2 entryvisdt randdt);                  
    by patid;                                                                                                                                     
    %if entrystratcat2 ne . %then %do;
      if entrystratcat2=2 and lmpdt <= entryvisdt; 
    %end;
    %else %do;
      if stratcat2=2 and lmpdt <= randdt;
    %end; 
run; 
%mend evw0380; 

%evw0380; 

%macro dates(); 
/*Calculate missing lmpdts and cutoffdts for different stratcats*/
data dates miss_cutoffdt;
    merge dervhope.master(in=inmaster keep=patid entrystratcat2 stratcat2 entryvisdt randdt)
          evw0380(in=in0380)
          evw0379(in=in0379)
          QLW0360(in=in0360)
          anstab(in=inanstab);
    by patid;     
    if inmaster;
    length cutoffdt 5;  

    /*This block of code derives the cutoffdt using the participant information at the time of entryvisit*/
    if entrystratcat2 ne . then do;
        /*If currently pregnant and missing lmpdt and non-missing gesage then do calculation below for lmpdt*/
        if entrystratcat2 in (2) and lmpdt=. and anstab_gesage ne . then lmpdt=entryvisdt-(anstab_gesage*7); 
         /*For the lmpdt calculation, there's a pregdt hierarchy: pregdt0379--> pregdt0360 --> anstab_pregdt*/ 
        else if entrystratcat2 in (3,4) and lmpdt=. then do; 
            if pregdt0379 ne . and gesage0379 ne . then lmpdt=pregdt0379-(gesage0379*7);
                else if pregdt0360 ne . and gesage0360 ne . then lmpdt=pregdt0360-(gesage0360*7);
                else if anstab_pregdt ne . and anstab_gesage ne . then lmpdt=anstab_pregdt-(anstab_gesage*7);
        end; 
        /*If lmpdt missing bc no valid gesage, then assume 40 weeks according to Jessica document and combine with first-nonmissing pregdt*/  
        if lmpdt=. and (pregdt0379 ne . or pregdt0360 ne . or anstab_pregdt ne .) then do; 
            temp_pregdt=coalesce(pregdt0379, pregdt0360, anstab_pregdt); /*Use first non-missing date in this order*/
            if entrystratcat2 in (3,4) then lmpdt=temp_pregdt-(40*7); /*JESSICA document says to use 40 for gesage if no other value is available*/
        end; 
        
        /*Cutoffdt for stratcats 2,3,4 is lmpdt - 6 months*/
        if entrystratcat2 in (2,3,4) and lmpdt ne . then cutoffdt=intnx('month', lmpdt, -6, 'same');     
        /*Cutoffdt for stratcats 1,5 is enrtyvisdt - 1 year*/
        else if entrystratcat2 not in (2,3,4) and entryvisdt ne . then cutoffdt=intnx('year', entryvisdt, -1, 'same');
    end; 

    /*If the cutoffdt is not able to be calculated using information at the time of entryvisit, then the information at the time of enrollment is used*/
    if cutoffdt = . then do;
        /*If currently pregnant and missing lmpdt and non-missing gesage then do calculation below for lmpdt*/
        if stratcat2 in (2) and lmpdt=. and anstab_gesage ne . then lmpdt=randdt-(anstab_gesage*7); 
         /*For the lmpdt calculation, there's a pregdt hierarchy: pregdt0379--> pregdt0360 --> anstab_pregdt*/ 
        else if stratcat2 in (3,4) and lmpdt=. then do; 
            if pregdt0379 ne . and gesage0379 ne . then lmpdt=pregdt0379-(gesage0379*7);
                else if pregdt0360 ne . and gesage0360 ne . then lmpdt=pregdt0360-(gesage0360*7);
                else if anstab_pregdt ne . and anstab_gesage ne . then lmpdt=anstab_pregdt-(anstab_gesage*7);
        end; 
        /*If lmpdt missing bc no valid gesage, then assume 40 weeks according to Jessica document and combine with first-nonmissing pregdt*/  
        if lmpdt=. and (pregdt0379 ne . or pregdt0360 ne . or anstab_pregdt ne .) then do; 
            temp_pregdt=coalesce(pregdt0379, pregdt0360, anstab_pregdt); /*Use first non-missing date in this order*/
            if stratcat2 in (3,4) then lmpdt=temp_pregdt-(40*7); /*JESSICA document says to use 40 for gesage if no other value is available*/
        end; 
        /*Cutoffdt for stratcats 2,3,4 is lmpdt - 6 months*/
        if stratcat2 in (2,3,4) and lmpdt ne . then cutoffdt=intnx('month', lmpdt, -6, 'same');     
        /*Cutoffdt for stratcats 1,5 is enrtyvisdt - 1 year*/
        else if stratcat2 not in (2,3,4) and randdt ne . then cutoffdt=intnx('year', randdt, -1, 'same');
        
        /*This will be temporary, but this flag identifies when a participant had an entryvisit but the info could not be used to calculate cutoffdt so enrollment 
          info was used instead*/
        if entryvisdt ne . and cutoffdt ne . then entry_happen_used_enroll=1;

    end; 

    /*Print patids with no cutoffdts to log and output to separate dataset so they can be investigated further. Print data with cutoffdts
    to dates dataset*/
    if cutoffdt = . then do; 
      output miss_cutoffdt; 
       put 'WARNING: No cutoffdt available for ' 
            patid= entrystratcat2= stratcat2= randdt= entryvisdt= lmpdt= anstab_pregdt= anstab_gesage=
            pregdt0379= pregdt0360= gesage0379= gesage0360=;
    end; 
    else if cutoffdt ne . then output dates;  
    
    label 
      temp_pregdt='First non-missing pregdt (selected in the following order: pregdt0379 pregdt0360 anstab_pregdt) value used as a last resort in lmpdt calc'
      cutoffdt = 'Reflects the date 6 months before lmpdt for patids with stratcat2 = (2,3,4) or reflects the date 1 year before entryvisdt for 
                  patids not in stratcat2 = (2,3,4)';

    format cutoffdt anstab_pregdt pregdt0379 pregdt0360 temp_pregdt date9. ; 
run; 

/*Store number of obs with missing cutoffdts into macro var*/
proc sql noprint; 
  select count(*) into: miss_cutoffdt_obs from miss_cutoffdt; 
quit; 

/*Print obs with missing cutoffdts to CSV for easier readability*/
%if &miss_cutoffdt_obs>0 %then %do; 
  ods csv file="&outrtf./miss_cutoffdt.csv"; 
    proc print data=miss_cutoffdt; 
      var patid entrystratcat2 stratcat2 randdt entryvisdt lmpdt anstab_pregdt anstab_gesage 
        pregdt0379 pregdt0360 gesage0379 gesage0360;
      format anstab_pregdt pregdt0379 pregdt0360 date9. ; 
    run; 
  ods csv close; 
%end; 

%mend dates; 

%dates(); 
