# libs ----
pacman::p_load(
    tidyverse,
    ggplot2,
    patchwork
)

setwd(this.path::here())

# data ----
dat_raw <- read_csv("Behavioral_GNG.csv")

dat <- dat_raw %>% 
    mutate(
        resp = if_else(resp == -99, NA_real_, resp),
        rt = if_else(resp == -99, NA_real_, rt),
        no_go_flag = if_else(est == 2, 1, 0)
    ) %>% 
    group_by(SU) %>% 
    mutate(
        trial = as.factor(cumsum(no_go_flag)),
        trial_num = as.numeric(as.character(trial))
    ) %>% 
    ungroup() %>% 
    group_by(SU, trial) %>% 
    mutate(
        trial_len = row_number()
    )
dat

# model betas ----

betas <- dat %>% 
    filter(!is.na(rt)) %>% 
    ungroup() %>% 
    group_by(SU, trial) %>% 
    group_split() %>% 
    map_dfr(., function(X){
        mdl <- lm(rt ~ trial_len, data = X)
        mdl_coef <- tibble(
            intercept = coef(mdl)[1],
            beta      = coef(mdl)[2],
            SU        = X$SU[1],
            trial     = X$trial[1]
        )
        return(mdl_coef)
    })

# lmer rt mdl ----

rt_mdl <- lmerTest::lmer(
    data = dat,
    log(rt) ~ trial_len + (trial_len|SU)
)
summary(rt_mdl)


rt_mdl_emm <- emmeans::emmeans(
    rt_mdl,
    ~ trial_len,
    type = "response",
    at = list(trial_len = seq(1, 8, 1))
)
rt_mdl_emm

# beta mdl ----

rt_beta_mdl <- lme4::glmer(
    data = dat,
    rt ~ trial_len + (trial_len | SU),
    family = Gamma(link = "log")
)
summary(rt_beta_mdl)

rt_beta_emm <- emmeans::emmeans(
    rt_beta_mdl,
    ~ trial_len,
    type = "response",
    at = list(trial_len = seq(1, 8, 1))
)
rt_beta_emm

# beta mdl consider trial position ----

rt_beta_trial_mdl <- lme4::glmer(
    data = dat %>%
        group_by(SU) %>% 
        mutate(
        trial_len = scales::rescale(trial_len, to = c(0, 1)),
        trial_num = scales::rescale(trial_num, to = c(0, 1))
    ),
    rt ~ trial_len * trial_num + (trial_len | SU) + (1 | trial_num),
    family = Gamma(link = "log")
)
summary(rt_beta_trial_mdl)

rt_beta_trial_emm <- emmeans::emmeans(
    rt_beta_trial_mdl,
    ~ trial_len | trial_num,
    type = "response",
    at = list(trial_len = seq(0, 1, 0.25),
              trial_num = seq(0, 1, 0.25))
)
rt_beta_trial_emm


# plots ----
p1 <- dat %>% 
    filter(!is.na(rt)) %>% 
    ggplot(aes(
        trial_len, rt
    )) +
    geom_point(aes(group = interaction(SU, trial))) +
    geom_smooth(method = "lm", se = FALSE, aes(group = interaction(SU, trial)),
                alpha = 0.25, color = "gray", linewidth = 0.5) +
    geom_smooth(method = "lm", se = FALSE, aes(group = SU),
                alpha = 1, color = "black") +
    facet_wrap(~SU, scale = "free_y") +
    theme_classic()
p1

p2 <- betas %>% 
    ggplot(aes(
        as.factor(SU), beta
    )) +
    geom_violin() +
    geom_point(size = 1.5, shape = 21) +
    geom_hline(yintercept = 0, linetype = "dashed") +
    ggpubr::theme_classic2()
p2

p3 <- betas %>% 
    ggplot(aes(
        beta
    )) +
    geom_density() +
    geom_vline(xintercept = 0, linetype = "dashed") +
    ggpubr::theme_classic2()
p3

p4 <- rt_mdl_emm %>% 
    broom.mixed::tidy(., conf.int = TRUE) %>% 
    ggplot(aes(
        trial_len, response
    )) +
    geom_line() +
    geom_ribbon(aes(ymin = conf.low, ymax = conf.high),
                alpha = 0.25) +
    ggpubr::theme_classic2()
p4

p5 <- rt_beta_emm %>% 
    broom.mixed::tidy(., conf.int = TRUE) %>% 
    ggplot(aes(
        trial_len, response
    )) +
    geom_line() +
    geom_ribbon(aes(ymin = conf.low, ymax = conf.high),
                alpha = 0.25) +
    ggpubr::theme_classic2()
p5

## rt over go's and trials ----
p6_dat <- dat %>%
        group_by(SU) %>% 
        mutate(
        trial_len = scales::rescale(trial_len, to = c(0, 1)),
        trial_num = scales::rescale(trial_num, to = c(0, 1)),
        bin_trial_num = ntile(trial_num, 5)
    )

p6 <- rt_beta_trial_emm %>% 
    broom.mixed::tidy(., conf.int = TRUE) %>% 
    ggplot(aes(
        trial_len, response, group = trial_num
    )) +
    geom_line() +
    geom_ribbon(aes(ymin = conf.low, ymax = conf.high),
                alpha = 0.1, fill = "gray") +
    ggpubr::theme_classic2() +
    facet_wrap(~trial_num)
p6

p7 <- rt_beta_trial_emm %>% 
    broom.mixed::tidy(., conf.int = TRUE) %>% 
    ggplot(aes(
        trial_num, response
    )) +
    geom_line(linewidth = 3, aes(group = trial_len, color = trial_len)) 
p7

p8 <- p6_dat %>% 
    drop_na() %>% 
    group_by(SU, bin_trial_num) %>% 
    summarise(
        rt = mean(rt)
    ) %>% 
    ggplot(aes(
        bin_trial_num, rt
    )) +
    stat_summary(
        fun.data = "mean_se",
        geom = "pointrange",
        color = "purple",
        aes(group = bin_trial_num)
    ) +
    stat_summary(
        fun.data = "mean_se",
        geom = "line",
        color = "purple"
    ) +
    geom_boxplot(aes(group = as.factor(bin_trial_num)),
                fill = NA, trim = TRUE, outlier.shape = NA)
p8


